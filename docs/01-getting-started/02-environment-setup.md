---
layout: default
title: Environment Setup
parent: Getting Started
nav_order: 2
difficulty: beginner
---

# Environment Setup
{: .no_toc }

Set up your development environment for OpenBMC.
{: .fs-6 .fw-300 }

## Table of Contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

## Overview

This guide covers three setup options:

| Option | Best For | Host OS |
|--------|----------|---------|
| **Native Linux** | Full performance, serious development | Ubuntu/Fedora |
| **Docker** | Quick start, Windows/macOS users | Any |
| **SDK Only** | Application development without full builds | Any |

Choose the option that fits your needs. For complete OpenBMC development, **Native Linux** is recommended.

---

## System Requirements

### Minimum Requirements

| Resource | Minimum | Recommended |
|----------|---------|-------------|
| **OS** | Ubuntu 20.04, Fedora 34 | Ubuntu 22.04, Fedora 38 |
| **RAM** | 16 GB | 32 GB |
| **Disk** | 100 GB free | 250 GB SSD |
| **CPU** | 4 cores | 8+ cores |

{: .warning }
Building OpenBMC is resource-intensive. Insufficient RAM will cause build failures.

---

## Option 1: Native Linux Setup (Recommended)

### Ubuntu 22.04 / 20.04

```bash
# Update system
sudo apt update && sudo apt upgrade -y

# Install required packages
sudo apt install -y \
    gawk wget git diffstat unzip texinfo gcc build-essential \
    chrpath socat cpio python3 python3-pip python3-pexpect \
    xz-utils debianutils iputils-ping python3-git python3-jinja2 \
    libegl1-mesa libsdl1.2-dev pylint xterm python3-subunit \
    mesa-common-dev zstd liblz4-tool

# Install additional useful tools
sudo apt install -y \
    curl vim tmux htop tree \
    libssl-dev libffi-dev

# Verify installation
echo "Checking installed tools..."
git --version
python3 --version
gcc --version
```

### Fedora 38 / 34

```bash
# Install required packages
sudo dnf install -y \
    gawk make wget tar bzip2 gzip python3 unzip perl patch \
    diffutils diffstat git cpp gcc gcc-c++ glibc-devel \
    texinfo chrpath ccache perl-Data-Dumper perl-Text-ParseWords \
    perl-Thread-Queue perl-bignum socat python3-pexpect \
    findutils which file cpio python python3-pip xz python3-GitPython \
    python3-jinja2 SDL-devel xterm rpcgen mesa-libGL-devel \
    perl-FindBin perl-File-Compare perl-File-Copy perl-locale \
    zstd lz4

# Verify installation
echo "Checking installed tools..."
git --version
python3 --version
gcc --version
```

### Clone OpenBMC Repository

```bash
# Create workspace directory
mkdir -p ~/openbmc-workspace
cd ~/openbmc-workspace

# Clone the repository
git clone https://github.com/openbmc/openbmc.git
cd openbmc

# Check available machines
ls meta-*/meta-*/conf/machine/*.conf | head -20
```

### Initialize Build Environment

```bash
# Source the environment script
# This sets up paths and creates the build directory
. setup romulus

# You're now in the build directory
# The terminal prompt changes to indicate the environment is active
```

{: .note }
`romulus` is a reference machine good for learning. Replace with your target machine for real development.

---

## Option 2: Docker Setup

Docker provides a consistent build environment across operating systems.

### Install Docker

**Ubuntu/Debian:**
```bash
# Install Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh

# Add user to docker group (logout/login required)
sudo usermod -aG docker $USER
```

**Windows/macOS:**
Download and install [Docker Desktop](https://www.docker.com/products/docker-desktop/).

### Using the OpenBMC Build Container

```bash
# Create workspace
mkdir -p ~/openbmc-workspace
cd ~/openbmc-workspace

# Clone OpenBMC
git clone https://github.com/openbmc/openbmc.git
cd openbmc

# Run build in container
docker run --rm -it \
    -v $(pwd):/home/openbmc/openbmc \
    -w /home/openbmc/openbmc \
    crops/poky:ubuntu-22.04 \
    /bin/bash -c ". setup romulus && bitbake obmc-phosphor-image"
```

### Custom Dockerfile (Alternative)

Create a `Dockerfile` for a customized environment:

```dockerfile
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    gawk wget git diffstat unzip texinfo gcc build-essential \
    chrpath socat cpio python3 python3-pip python3-pexpect \
    xz-utils debianutils iputils-ping python3-git python3-jinja2 \
    libegl1-mesa libsdl1.2-dev pylint xterm python3-subunit \
    mesa-common-dev zstd liblz4-tool locales \
    && rm -rf /var/lib/apt/lists/*

# Set locale
RUN locale-gen en_US.UTF-8
ENV LANG=en_US.UTF-8

# Create non-root user
RUN useradd -ms /bin/bash openbmc
USER openbmc
WORKDIR /home/openbmc

CMD ["/bin/bash"]
```

Build and use:
```bash
docker build -t openbmc-builder .
docker run --rm -it -v $(pwd):/home/openbmc/openbmc openbmc-builder
```

---

## Option 3: SDK Installation

The SDK allows cross-compiling applications without a full build environment.

### Generate SDK (requires full build first)

```bash
# In an initialized build environment
bitbake obmc-phosphor-image -c populate_sdk
```

The SDK installer is created at:
```
build/tmp/deploy/sdk/oecore-x86_64-arm1176jzs-toolchain-*.sh
```

### Install SDK

```bash
# Run the installer
./oecore-x86_64-arm1176jzs-toolchain-*.sh

# Default install location: /opt/openbmc-phosphor/VERSION
# Accept the default or specify a custom path
```

### Use SDK

```bash
# Source the environment
source /opt/openbmc-phosphor/VERSION/environment-setup-arm1176jzs-openbmc-linux-gnueabi

# Verify cross-compiler
$CC --version
# Should show arm-openbmc-linux-gnueabi-gcc

# Cross-compile a simple program
echo 'int main() { return 0; }' > test.c
$CC test.c -o test
file test
# Should show: ELF 32-bit LSB executable, ARM
```

---

## QEMU Setup

QEMU allows testing OpenBMC without physical hardware.

### Install QEMU

**Ubuntu:**
```bash
sudo apt install -y qemu-system-arm
```

**Fedora:**
```bash
sudo dnf install -y qemu-system-arm
```

### Verify QEMU

```bash
qemu-system-arm --version
# Should be version 4.0 or later
```

QEMU usage is covered in the [First Build]({% link docs/01-getting-started/03-first-build.md %}) guide.

---

## IDE Setup (VS Code)

VS Code provides excellent support for OpenBMC development.

### Install VS Code

Download from [code.visualstudio.com](https://code.visualstudio.com/)

### Recommended Extensions

Install these extensions:
- **C/C++** (Microsoft) - IntelliSense, debugging
- **Remote - SSH** - Remote development
- **Remote - Containers** - Docker development
- **Python** - Python support
- **YAML** - Recipe file editing
- **BitBake** - Yocto syntax highlighting

### Configure IntelliSense

Create `.vscode/c_cpp_properties.json`:

```json
{
    "configurations": [
        {
            "name": "OpenBMC",
            "includePath": [
                "${workspaceFolder}/**",
                "/path/to/sdk/sysroots/arm*/usr/include/**"
            ],
            "defines": [],
            "compilerPath": "/path/to/sdk/sysroots/x86_64*/usr/bin/arm-openbmc-linux-gnueabi-gcc",
            "cStandard": "c17",
            "cppStandard": "c++20",
            "intelliSenseMode": "linux-gcc-arm"
        }
    ],
    "version": 4
}
```

### VS Code with Docker Dev Containers

Create `.devcontainer/devcontainer.json`:

```json
{
    "name": "OpenBMC Dev",
    "image": "crops/poky:ubuntu-22.04",
    "customizations": {
        "vscode": {
            "extensions": [
                "ms-vscode.cpptools",
                "ms-python.python"
            ]
        }
    },
    "mounts": [
        "source=${localWorkspaceFolder},target=/home/openbmc/openbmc,type=bind"
    ],
    "remoteUser": "pokyuser"
}
```

---

## Verify Your Setup

Run this checklist:

```bash
# Check Git
git --version
# ✓ Git 2.25 or later

# Check Python
python3 --version
# ✓ Python 3.8 or later

# Check disk space
df -h ~
# ✓ 100GB+ free

# Check RAM
free -h
# ✓ 16GB+ total

# Check QEMU
qemu-system-arm --version
# ✓ QEMU 4.0 or later

# If using Docker
docker --version
# ✓ Docker 20.10 or later
```

---

## Next Steps

Your environment is ready! Continue to:

➡️ **[First Build]({% link docs/01-getting-started/03-first-build.md %})** - Build OpenBMC and run in QEMU

### Debug Builds (Optional)

For development and debugging, you may want to configure debug builds with sanitizers:

```bash
# Add to build/conf/local.conf for debug builds
DEBUG_BUILD = "1"
EXTRA_IMAGE_FEATURES += "dbg-pkgs"
```

For comprehensive debugging tools including ASan, UBSan, TSan, Valgrind, and kernel debug options, see the **[Linux Debug Tools Guide]({% link docs/05-advanced/08-linux-debug-tools-guide.md %})**.

---

## Troubleshooting

### Build fails with "out of memory"

Increase system RAM or add swap:
```bash
sudo fallocate -l 8G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
```

### Permission denied with Docker

Ensure user is in the docker group:
```bash
sudo usermod -aG docker $USER
# Then logout and login
```

### "locale" errors during build

Set locale:
```bash
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8
```

---

{: .note }
**Tested on**: Ubuntu 22.04, Fedora 38, Docker on Windows 11
