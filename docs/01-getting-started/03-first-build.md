---
layout: default
title: First Build
parent: Getting Started
nav_order: 3
difficulty: beginner
prerequisites:
  - environment-setup
---

# First Build
{: .no_toc }

Build and run your first OpenBMC image in QEMU.
{: .fs-6 .fw-300 }

## Table of Contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

## Overview

This guide walks you through building an OpenBMC image and running it in the QEMU emulator.

---

## Clone OpenBMC

```bash
# Clone the OpenBMC repository
git clone https://github.com/openbmc/openbmc.git
cd openbmc
```

---

## Initialize Build Environment

```bash
# Set up environment for romulus machine (QEMU-compatible)
. setup romulus

# This creates a build directory and configures for romulus
```

---

## Build the Image

```bash
# Build the full image (this takes 1-4 hours first time)
bitbake obmc-phosphor-image

# For faster iteration, build minimal image
bitbake obmc-phosphor-image-minimal
```

### Build Tips

- First build downloads many sources - be patient
- Subsequent builds are much faster (incremental)
- Use `bitbake -c cleansstate <recipe>` to rebuild a package

---

## Run in QEMU

### Locate the Image

```bash
# Find the built image
ls tmp/deploy/images/romulus/

# Key files:
# - obmc-phosphor-image-romulus.static.mtd (flash image)
# - fitImage-obmc-phosphor-initramfs-romulus (kernel)
```

### Start QEMU

```bash
# Using the provided QEMU script
./meta-romulus/conf/run-qemu.sh

# Or manually:
qemu-system-arm -m 256 \
    -M romulus-bmc \
    -nographic \
    -drive file=tmp/deploy/images/romulus/obmc-phosphor-image-romulus.static.mtd,format=raw,if=mtd \
    -net nic \
    -net user,hostfwd=tcp::2222-:22,hostfwd=tcp::2443-:443,hostfwd=tcp::2623-:623
```

### Default Credentials

| Interface | Username | Password |
|-----------|----------|----------|
| SSH | root | 0penBmc |
| Redfish | root | 0penBmc |
| WebUI | root | 0penBmc |

---

## Verify the Build

### Access via SSH

```bash
# Connect to QEMU (port 2222)
ssh -p 2222 root@localhost
# Password: 0penBmc

# Check BMC state
obmcutil state
```

### Access via Redfish

```bash
# Query Redfish API
curl -k -u root:0penBmc https://localhost:2443/redfish/v1/

# Get system info
curl -k -u root:0penBmc https://localhost:2443/redfish/v1/Systems/system
```

### Access WebUI

Open in browser: `https://localhost:2443/`

---

## Common Operations

### Check System State

```bash
# On BMC
obmcutil state

# Shows:
# BMC state: Ready
# Chassis state: On/Off
# Host state: Running/Off
```

### Power Control

```bash
# Power on host
obmcutil poweron

# Power off host
obmcutil poweroff

# Reboot host
obmcutil hostreboot
```

### View Sensors

```bash
# List sensors
busctl tree xyz.openbmc_project.Sensor

# Via Redfish
curl -k -u root:0penBmc \
    https://localhost:2443/redfish/v1/Chassis/chassis/Sensors
```

---

## Troubleshooting

### Build Fails

```bash
# Check for missing dependencies
bitbake obmc-phosphor-image -c checkpkg

# Clean and rebuild
bitbake -c cleansstate <problematic-recipe>
bitbake obmc-phosphor-image
```

### QEMU Won't Start

```bash
# Check QEMU is installed
qemu-system-arm --version

# Verify image exists
ls -la tmp/deploy/images/romulus/*.mtd
```

### Can't Connect

```bash
# Check QEMU is running
ps aux | grep qemu

# Verify port forwarding
netstat -tlnp | grep 2222
```

---

## Next Steps

- [OpenBMC Overview]({% link docs/02-architecture/01-openbmc-overview.md %}) - Understand the architecture
- [D-Bus Guide]({% link docs/02-architecture/02-dbus-guide.md %}) - Learn D-Bus communication
- [Sensor Guide]({% link docs/03-core-services/01-dbus-sensors-guide.md %}) - Configure sensors

---

{: .note }
**Tested on**: Ubuntu 22.04, OpenBMC master branch
