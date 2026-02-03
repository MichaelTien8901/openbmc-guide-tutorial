---
layout: default
title: Building QEMU
parent: Getting Started
nav_order: 5
difficulty: intermediate
prerequisites:
  - environment-setup
---

# Building QEMU for OpenBMC
{: .no_toc }

Build QEMU from source when your distribution's package lacks ast2600-evb support.
{: .fs-6 .fw-300 }

## Table of Contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

## When You Need This Guide

Stock QEMU from Linux distribution package managers often **lacks ASPEED machine support**:

| Distribution | Package QEMU Version | ast2600-evb Support |
|--------------|---------------------|---------------------|
| Ubuntu 20.04 | QEMU 4.2 | ❌ No |
| Ubuntu 22.04 | QEMU 6.2 | ⚠️ Partial |
| Ubuntu 24.04 | QEMU 8.2 | ✅ Yes |
| Fedora 38+ | QEMU 7.2+ | ✅ Yes |
| Debian 11 | QEMU 5.2 | ❌ No |
| Debian 12 | QEMU 7.2 | ✅ Yes |

### Check Your QEMU Version

```bash
# Check version
qemu-system-arm --version

# Check if ast2600-evb is available
qemu-system-arm -machine help | grep ast2600
```

If `ast2600-evb` is not listed, you need to build QEMU from source.

---

## Option 1: Use OpenBMC's Built-in QEMU (Recommended)

The OpenBMC build system includes a QEMU recipe with full ASPEED support. This is the easiest option.

### Build QEMU via BitBake

```bash
cd openbmc

# Initialize environment (if not already done)
. setup ast2600-evb

# Build QEMU native tool
bitbake qemu-system-native

# Find the built QEMU
ls tmp/work/x86_64-linux/qemu-system-native/*/image/usr/bin/qemu-system-arm
```

### Use the Built QEMU

```bash
# Set path to OpenBMC's QEMU
QEMU_PATH="tmp/work/x86_64-linux/qemu-system-native/*/image/usr/bin"

# Run with OpenBMC's QEMU
$QEMU_PATH/qemu-system-arm -m 1G \
    -M ast2600-evb \
    -nographic \
    -drive file=tmp/deploy/images/ast2600-evb/obmc-phosphor-image-ast2600-evb.static.mtd,format=raw,if=mtd \
    -net nic \
    -net user,hostfwd=tcp::2222-:22,hostfwd=tcp::2443-:443,hostfwd=udp::2623-:623
```

### Create a Convenience Script

```bash
#!/bin/bash
# save as: run-qemu.sh

OPENBMC_DIR="${OPENBMC_DIR:-$(pwd)}"
QEMU=$(find $OPENBMC_DIR/tmp/work/x86_64-linux/qemu-system-native -name qemu-system-arm -type f | head -1)
IMAGE="$OPENBMC_DIR/tmp/deploy/images/ast2600-evb/obmc-phosphor-image-ast2600-evb.static.mtd"

if [ ! -f "$QEMU" ]; then
    echo "Error: QEMU not found. Run 'bitbake qemu-system-native' first."
    exit 1
fi

$QEMU -m 1G \
    -M ast2600-evb \
    -nographic \
    -drive file=$IMAGE,format=raw,if=mtd \
    -net nic \
    -net user,hostfwd=tcp::2222-:22,hostfwd=tcp::2443-:443,hostfwd=udp::2623-:623
```

---

## Option 2: Build QEMU from Source

Build QEMU directly from upstream source for use outside the OpenBMC build environment.

### Install Build Dependencies

```bash
# Ubuntu/Debian
sudo apt update
sudo apt install -y \
    git \
    build-essential \
    ninja-build \
    pkg-config \
    libglib2.0-dev \
    libpixman-1-dev \
    libslirp-dev \
    python3 \
    python3-venv

# Fedora
sudo dnf install -y \
    git \
    gcc \
    g++ \
    ninja-build \
    glib2-devel \
    pixman-devel \
    libslirp-devel \
    python3
```

### Clone and Build QEMU

```bash
# Clone QEMU (use version 8.0+ for best ASPEED support)
git clone https://github.com/qemu/qemu.git
cd qemu
git checkout v8.2.0  # or latest stable

# Configure for ARM system emulation only (faster build)
./configure \
    --target-list=arm-softmmu \
    --enable-slirp \
    --disable-docs \
    --disable-werror

# Build (use -j for parallel compilation)
make -j$(nproc)

# Verify ast2600-evb is available
./build/qemu-system-arm -machine help | grep ast2600
```

### Install System-Wide (Optional)

```bash
# Install to /usr/local
sudo make install

# Verify installation
qemu-system-arm --version
qemu-system-arm -machine help | grep ast2600
```

### Install to Custom Location

```bash
# Install to home directory
./configure \
    --target-list=arm-softmmu \
    --prefix=$HOME/qemu \
    --enable-slirp

make -j$(nproc)
make install

# Add to PATH
echo 'export PATH="$HOME/qemu/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
```

---

## Option 3: Use Container with QEMU

Run QEMU inside a container that has proper ASPEED support.

### Docker with QEMU

```dockerfile
# Dockerfile.qemu
FROM ubuntu:24.04

RUN apt-get update && apt-get install -y \
    qemu-system-arm \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /openbmc
```

```bash
# Build container
docker build -t openbmc-qemu -f Dockerfile.qemu .

# Run QEMU in container (mount image directory)
docker run -it --rm \
    -v $(pwd)/tmp/deploy/images:/images \
    -p 2222:2222 -p 2443:2443 -p 2623:2623/udp \
    openbmc-qemu \
    qemu-system-arm -m 1G -M ast2600-evb -nographic \
    -drive file=/images/ast2600-evb/obmc-phosphor-image-ast2600-evb.static.mtd,format=raw,if=mtd \
    -net nic \
    -net user,hostfwd=tcp::2222-:22,hostfwd=tcp::2443-:443,hostfwd=udp::2623-:623
```

---

## Verifying QEMU Setup

### Check Available Machines

```bash
# List all ASPEED machines
qemu-system-arm -machine help | grep -i aspeed

# Expected output includes:
# ast2500-evb     Aspeed AST2500 EVB (ARM926EJ-S)
# ast2600-evb     Aspeed AST2600 EVB (Cortex-A7)
# palmetto-bmc    OpenPOWER Palmetto BMC (ARM926EJ-S)
# romulus-bmc     OpenPOWER Romulus BMC (ARM1176)
# witherspoon-bmc OpenPOWER Witherspoon BMC (ARM1176)
```

### Test Run

```bash
# Quick test (will fail without image, but confirms QEMU works)
qemu-system-arm -M ast2600-evb -nographic -serial null
# Press Ctrl+A, X to exit
```

---

## Machine Selection Reference

| Machine | SoC | CPU | Memory | Use Case |
|---------|-----|-----|--------|----------|
| **ast2600-evb** | AST2600 | Cortex-A7 (dual) | 1GB | Modern development (recommended) |
| ast2500-evb | AST2500 | ARM926EJ-S | 512MB | Legacy compatibility |
| romulus-bmc | AST2500 | ARM1176 | 256MB | IBM OpenPOWER reference |
| witherspoon-bmc | AST2500 | ARM1176 | 256MB | IBM OpenPOWER reference |

{: .tip }
Use **ast2600-evb** for new development. It has more memory (1GB vs 256MB), a modern CPU, and represents current hardware.

---

## Troubleshooting

### "Machine type not found"

```
qemu-system-arm: -M ast2600-evb: unsupported machine type
```

**Solution**: Your QEMU version is too old. Build from source using this guide.

### Build Fails with Missing Dependencies

```bash
# Install all possible dependencies
sudo apt install -y \
    libglib2.0-dev libpixman-1-dev libslirp-dev \
    libcap-ng-dev libattr1-dev libaio-dev \
    libnuma-dev libseccomp-dev
```

### Slow Performance

```bash
# Enable KVM if running ARM on ARM host
qemu-system-arm -M ast2600-evb -enable-kvm ...

# For x86 host, KVM won't help (cross-architecture)
# Allocate more CPU cores
qemu-system-arm -M ast2600-evb -smp 2 ...
```

---

## Next Steps

- [First Build]({% link docs/01-getting-started/03-first-build.md %}) - Build and run OpenBMC
- [Development Workflow]({% link docs/01-getting-started/04-development-workflow.md %}) - Iterate quickly with devtool

---

{: .note }
**Tested on**: Ubuntu 22.04/24.04, Fedora 38/39, QEMU 7.2-8.2
