# syntax=docker/dockerfile:1
ARG TOOLCHAIN_BASE=public.ecr.aws/docker/library/ubuntu:24.04@sha256:534baea6a22c03a63003dbc8dbe78fe34bc0d7e595d9a9dc9834884ff530eb55
ARG BASE_IMAGE=public.ecr.aws/docker/library/ubuntu:24.04@sha256:534baea6a22c03a63003dbc8dbe78fe34bc0d7e595d9a9dc9834884ff530eb55

FROM ${TOOLCHAIN_BASE} AS toolchain-builder
ARG BUILD_JOBS=2
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
    autoconf automake autotools-dev bc bison build-essential ca-certificates \
    cmake curl flex gawk gperf git libexpat1-dev libgmp-dev libmpc-dev \
    libmpfr-dev libtool patchutils python3 texinfo xz-utils zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*
COPY sources.lock.json /recipe/sources.lock.json
COPY .cache/ /archives/
COPY scripts/build-toolchain.sh /recipe/build-toolchain.sh
RUN bash /recipe/build-toolchain.sh

FROM ${BASE_IMAGE} AS development
ARG BUILD_JOBS=2
ARG UBUNTU_VERSION=24.04
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential ca-certificates device-tree-compiler git libgmp-dev \
    libmpc3 libmpfr6 make patch python3 xz-utils \
    && rm -rf /var/lib/apt/lists/*
COPY .cache/spike-v1.1.0.tar.gz /archives/spike-v1.1.0.tar.gz
COPY scripts/build-spike.sh /recipe/build-spike.sh
COPY patches/ /recipe/patches/
RUN bash /recipe/build-spike.sh && rm -rf /archives /recipe
COPY --from=toolchain-builder /opt/riscv /opt/riscv
COPY sources.lock.json /usr/share/riscv-dev-env/sources.lock.json
COPY tests/ /usr/share/riscv-dev-env/tests/
COPY scripts/smoke-test.sh /usr/local/bin/riscv-smoke-test
ENV PATH=/opt/riscv/bin:/opt/spike/bin:$PATH
LABEL org.opencontainers.image.title="RISC-V development environment prototype" \
    org.opencontainers.image.version="ubuntu-${UBUNTU_VERSION}-gcc16.2-spike1.1" \
    org.opencontainers.image.description="Ubuntu, GCC 16.2.0/Newlib and Spike v1.1.0; Phase 1 prototype for DevPartners #47"
RUN chmod 755 /usr/local/bin/riscv-smoke-test \
    && riscv-smoke-test \
    && mkdir -p /usr/share/riscv-dev-env \
    && dpkg-query -W > /usr/share/riscv-dev-env/ubuntu-packages.txt \
    && useradd --create-home --uid 1001 riscv \
    && mkdir -p /workspace && chown riscv:riscv /workspace
USER riscv
WORKDIR /workspace
CMD ["bash"]
