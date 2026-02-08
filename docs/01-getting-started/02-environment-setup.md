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
. setup ast2600-evb

# You're now in the build directory
# The terminal prompt changes to indicate the environment is active
```

{: .note }
`ast2600-evb` is an AST2600-based evaluation board, ideal for learning modern OpenBMC. Replace with your target machine for production development.

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
    /bin/bash -c ". setup ast2600-evb && bitbake obmc-phosphor-image"
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

**Ubuntu 24.04+ / Fedora 38+:**
```bash
# Ubuntu
sudo apt install -y qemu-system-arm

# Fedora
sudo dnf install -y qemu-system-arm
```

### Verify QEMU Has ASPEED Support

```bash
# Check version (need 7.0+ for ast2600-evb)
qemu-system-arm --version

# Verify ast2600-evb machine is available
qemu-system-arm -machine help | grep ast2600
```

{: .warning }
**Older distributions** (Ubuntu 20.04/22.04, Debian 11) may not have ast2600-evb support in their package QEMU. If `grep ast2600` returns nothing, see [Building QEMU]({% link docs/01-getting-started/05-qemu-build.md %}) to build from source or use OpenBMC's built-in QEMU.

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

### VS Code Dev Container (Recommended for Docker Users)

This project includes a ready-to-use Dev Container configuration that provides a complete OpenBMC build environment with pre-configured tools, extensions, and build caching.

#### Prerequisites

- [VS Code](https://code.visualstudio.com/) with the [Dev Containers](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-containers) extension
- [Docker Desktop](https://www.docker.com/products/docker-desktop/) (Windows/macOS) or Docker Engine (Linux)

#### Directory Layout

The Dev Container expects your workspace to look like this:

```
your-workspace/
├── openbmc/                    # OpenBMC source (cloned from GitHub)
└── openbmc-guide-tutorial/     # This repository (contains .devcontainer/)
```

{: .warning }
You **must** clone the `openbmc` repository as a sibling directory before opening the Dev Container. The container will fail to start if it is missing.

#### Setup Steps

```bash
# 1. Create workspace and clone both repos side by side
mkdir -p ~/openbmc-workspace && cd ~/openbmc-workspace
git clone https://github.com/openbmc/openbmc.git
git clone https://github.com/michaeltien8901/openbmc-guide-tutorial.git

# 2. Open the tutorial repo in VS Code
code openbmc-guide-tutorial
```

Then in VS Code, press **F1** → **Dev Containers: Reopen in Container**. The first build takes several minutes; subsequent opens use cached layers.

#### What You Get

| Feature | Details |
|---------|---------|
| **Base image** | Ubuntu 22.04 with all Yocto/BitBake dependencies |
| **User** | `openbmc` with `sudo` access; UID auto-mapped to your host UID |
| **Build caching** | `sstate-cache` and `downloads` persist in Docker volumes across rebuilds |
| **SSH agent** | Forwarded from host — use `ssh-add -l` to verify |
| **Build env** | `oe-init-build-env` sourced automatically; `PARALLEL_MAKE` and `BB_NUMBER_THREADS` set to `$(nproc)` |
| **QEMU** | `qemu-system-arm` pre-installed for testing |
| **Extensions** | C/C++, Python, YAML, BitBake, GitLens, Git Graph, Code Spell Checker |
| **Forwarded ports** | 2222 (BMC SSH), 2443 (BMC HTTPS/Redfish), 2623 (BMC IPMI) |

#### Building OpenBMC Inside the Container

Once the container starts, the terminal is already inside `/workspace/openbmc` with the build environment initialized:

```bash
# Build the full image
bitbake obmc-phosphor-image

# Or build a single recipe
bitbake phosphor-webui
```

#### Build Caching with Docker Volumes

BitBake uses two large directories during builds:

- **`downloads/`** (`DL_DIR`) — upstream source tarballs fetched from the internet (several GB)
- **`sstate-cache/`** (`SSTATE_DIR`) — shared state cache of previously compiled outputs (saves hours on rebuilds)

The Dev Container mounts both as **Docker named volumes** rather than bind mounts:

```
source=openbmc-downloads,target=/workspace/openbmc/build/downloads,type=volume
source=openbmc-sstate-cache,target=/workspace/openbmc/build/sstate-cache,type=volume
```

This means:
- The data lives on your host in Docker-managed storage (`/var/lib/docker/volumes/`), **not** inside the container
- Deleting or rebuilding the container does not lose cached data
- **No `local.conf` configuration needed** — BitBake's default `DL_DIR` (`build/downloads/`) matches the mount target, so it works automatically
- **Shared across projects** — any container using the same volume name (e.g., `openbmc-downloads`) shares the same downloaded sources, avoiding redundant multi-GB downloads

{: .tip }
`docker system prune` does **not** delete named volumes. To fully reset build caches, explicitly remove them: `docker volume rm openbmc-sstate-cache openbmc-downloads`.

#### Using Dev Container from the CLI (Without VS Code)

You can use the Dev Container from any terminal using the [Dev Container CLI](https://github.com/devcontainers/cli):

```bash
# Install the CLI
npm install -g @devcontainers/cli

# Build and start the container
devcontainer up --workspace-folder ./openbmc-guide-tutorial

# Open an interactive shell inside it
devcontainer exec --workspace-folder ./openbmc-guide-tutorial bash

# Run a single command
devcontainer exec --workspace-folder ./openbmc-guide-tutorial \
    bitbake obmc-phosphor-image
```

{: .note }
The `--workspace-folder` points to the directory containing `.devcontainer/devcontainer.json`. The folder name does not matter — you can clone this repository as any name you like. The only requirement is that the `openbmc` source is cloned as a sibling directory next to it:

```
your-workspace/
├── openbmc/              # Must exist at ../openbmc relative to the folder below
└── any-name-you-want/    # Contains .devcontainer/devcontainer.json
```

#### Git Identity

The container does **not** set a git identity — it inherits your host's git configuration. If git prompts you to set `user.name` and `user.email`, configure them either on your host or inside the container:

```bash
git config --global user.name "Your Name"
git config --global user.email "you@example.com"
```

#### Troubleshooting Dev Container

**Container fails to start with "openbmc source not found":**
Ensure `openbmc/` is cloned as a sibling directory next to `openbmc-guide-tutorial/`.

**SSH agent not working (`ssh-add -l` shows error):**
Make sure your SSH agent is running on the host before opening the container:
```bash
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/id_ed25519
```

**File permission issues:**
The `updateRemoteUserUID` setting should handle this automatically. If you still see permission errors, rebuild the container: **F1** → **Dev Containers: Rebuild Container**.

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

➡️ **[Development Workflow]({% link docs/01-getting-started/04-development-workflow.md %})** - Learn devtool for rapid iteration

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
