FROM docker.io/library/ubuntu:22.04

LABEL maintainer "ops@semantic-network.com"
LABEL description="This image contains tools for Substrate blockchains runtimes."

ARG RUSTC_VERSION="1.69.0"
ENV RUSTC_VERSION=$RUSTC_VERSION
ENV DOCKER_IMAGE="tidelabs/srtool"
ENV PROFILE=release
ENV PACKAGE=tidechain-runtime
ENV BUILDER=builder
ARG UID=1001
ARG GID=1001

ENV SRTOOL_TEMPLATES=/srtool/templates
ENV CARGO_HOME="/cargo-home"
ENV RUSTUP_HOME="/rustup-home"

RUN groupadd -g $GID $BUILDER && \
    useradd --no-log-init  -m -u $UID -s /bin/bash -d /home/$BUILDER -r -g $BUILDER $BUILDER
RUN mkdir -p ${SRTOOL_TEMPLATES} && \
    mkdir -p ${CARGO_HOME} && \
    mkdir -p ${RUSTUP_HOME} && \
    mkdir /build && chown -R $BUILDER /build && \
    mkdir /out && chown -R $BUILDER /out

WORKDIR /tmp
ENV DEBIAN_FRONTEND=noninteractive

# Tooling
ARG SUBWASM_VERSION=0.19.1
ARG TERA_CLI_VERSION=0.2.4
ARG TOML_CLI_VERSION=0.2.4

# We first init as much as we can in the first layers
COPY ./scripts/* /srtool/
COPY ./templates ${SRTOOL_TEMPLATES}/

RUN apt update && \
    apt upgrade -y && \
    apt install --no-install-recommends -y \
        cmake pkg-config libssl-dev make protobuf-compiler \
        git clang bsdmainutils ca-certificates curl && \
    curl -L https://github.com/stedolan/jq/releases/download/jq-1.6/jq-linux64 --output /usr/bin/jq && chmod a+x /usr/bin/jq && \
    curl https://sh.rustup.rs -sSf | sh -s -- --default-toolchain $RUSTC_VERSION -y && \
    rm -rf /var/lib/apt/lists/* /tmp/* && apt clean

ENV PATH="/srtool:$CARGO_HOME/bin:$PATH"
RUN export PATH=$RUSTUP_HOME:$PATH && \
    curl -L https://github.com/chevdor/subwasm/releases/download/v${SUBWASM_VERSION}/subwasm_linux_amd64_v${SUBWASM_VERSION}.deb --output subwasm.deb && dpkg -i subwasm.deb && subwasm --version && \
    curl -L https://github.com/chevdor/tera-cli/releases/download/v${TERA_CLI_VERSION}/tera-cli_linux_amd64.deb --output tera_cli.deb && dpkg -i tera_cli.deb && tera --version && \
    curl -L https://github.com/chevdor/toml-cli/releases/download/v${TOML_CLI_VERSION}/toml_linux_amd64_v${TOML_CLI_VERSION}.deb --output toml.deb && dpkg -i toml.deb && toml --version && \
    mv -f $CARGO_HOME/bin/* /bin && \
    touch $CARGO_HOME/env && \
    rm -rf /tmp/*

# We copy the .cargo/bin away for 2 reasons.
# - easier with paths
# - mostly because it allows using a volume for .cargo without 'missing' the cargo bin when mapping an empty folder

# RUN echo 'export PATH="/srtool/:$PATH"' >> $HOME/.bashrc

# we copy those only at the end which makes testing of new scripts faster as the other layers are cached
COPY ./scripts/* /srtool/
COPY VERSION /srtool/
COPY RUSTC_VERSION /srtool/

USER $BUILDER
ENV RUSTUP_HOME="/home/${BUILDER}/rustup"
ENV CARGO_HOME="/home/${BUILDER}/cargo"

RUN echo $SHELL && \
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y && \
    . $CARGO_HOME/env && \
    rustup toolchain add stable ${RUSTC_VERSION} && \
    rustup target add wasm32-unknown-unknown --toolchain $RUSTC_VERSION && \
    chmod -R a+w $RUSTUP_HOME $CARGO_HOME && \
    rustup show && rustc -V

RUN git config --global --add safe.directory /build && \
    /srtool/version && \
    echo 'PATH=".:$PATH"' >> $HOME/.bashrc

VOLUME [ "/build", "$CARGO_HOME", "/out" ]
WORKDIR /srtool

CMD ["/srtool/build"]
