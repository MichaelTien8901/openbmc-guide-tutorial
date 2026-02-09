# OpenBMC Build Environment
# Based on Ubuntu 22.04 with all required dependencies
#
# Usage: Place this file at openbmc/.devcontainer/Dockerfile

FROM ubuntu:22.04

LABEL maintainer="OpenBMC Guide Tutorial"
LABEL description="OpenBMC development and build environment"

# Prevent interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# Set locale
ENV LANG=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8

# Layer 1: Yocto/BitBake core dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    gawk \
    wget \
    git \
    diffstat \
    unzip \
    texinfo \
    gcc \
    build-essential \
    chrpath \
    socat \
    cpio \
    python3 \
    python3-pip \
    python3-pexpect \
    xz-utils \
    debianutils \
    iputils-ping \
    python3-git \
    python3-jinja2 \
    pylint \
    python3-subunit \
    zstd \
    liblz4-tool \
    locales \
    curl \
    libssl-dev \
    libffi-dev \
    sudo \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Layer 2: Dev tools
RUN apt-get update && apt-get install -y --no-install-recommends \
    vim \
    tmux \
    htop \
    tree \
    && rm -rf /var/lib/apt/lists/*

# Layer 3: QEMU for testing
RUN apt-get update && apt-get install -y --no-install-recommends \
    qemu-system-arm \
    && rm -rf /var/lib/apt/lists/*

# Generate locale
RUN locale-gen en_US.UTF-8

# Create non-root user for builds (Yocto requirement)
RUN groupadd -g 1000 openbmc \
    && useradd -u 1000 -g openbmc -m -s /bin/bash openbmc \
    && echo "openbmc ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# Switch to non-root user
USER openbmc
WORKDIR /home/openbmc

# Default command
CMD ["/bin/bash"]
