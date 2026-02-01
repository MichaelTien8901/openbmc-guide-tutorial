# OpenBMC Build Environment
# Based on Ubuntu 22.04 with all required dependencies

FROM ubuntu:22.04

LABEL maintainer="OpenBMC Guide Tutorial"
LABEL description="OpenBMC development and build environment"

# Prevent interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# Set locale
ENV LANG=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8

# Install Yocto/BitBake dependencies
RUN apt-get update && apt-get install -y \
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
    libegl1-mesa \
    libsdl1.2-dev \
    pylint \
    xterm \
    python3-subunit \
    mesa-common-dev \
    zstd \
    liblz4-tool \
    locales \
    # Additional useful tools
    curl \
    vim \
    tmux \
    htop \
    tree \
    libssl-dev \
    libffi-dev \
    sudo \
    # QEMU for testing
    qemu-system-arm \
    && rm -rf /var/lib/apt/lists/*

# Generate locale
RUN locale-gen en_US.UTF-8

# Create non-root user for builds (Yocto requirement)
ARG USER_ID=1000
ARG GROUP_ID=1000
RUN groupadd -g ${GROUP_ID} openbmc \
    && useradd -u ${USER_ID} -g openbmc -m -s /bin/bash openbmc \
    && echo "openbmc ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# Set up workspace
RUN mkdir -p /workspace && chown openbmc:openbmc /workspace

# Switch to non-root user
USER openbmc
WORKDIR /workspace

# Set Git configuration (required for Yocto)
RUN git config --global user.email "openbmc@example.com" \
    && git config --global user.name "OpenBMC Builder" \
    && git config --global color.ui auto

# Default command
CMD ["/bin/bash"]
