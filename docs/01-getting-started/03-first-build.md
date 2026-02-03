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

This guide walks you through building an OpenBMC image and running it in QEMU.

{: .tip }
**QEMU is not a compromise** — it's the standard development environment used by professional OpenBMC developers. You'll have access to 100% of the OpenBMC software stack, including all D-Bus services, Redfish API, IPMI, and management interfaces.

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
# Set up environment for ast2600-evb machine (QEMU-compatible)
. setup ast2600-evb

# This creates a build directory and configures for ast2600-evb
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

QEMU provides a complete OpenBMC environment where you can:
- Access all D-Bus services exactly as on real hardware
- Test Redfish API endpoints with curl or any HTTP client
- Use ipmitool for IPMI commands
- SSH into the BMC and run commands
- Develop and debug services with full functionality

### Locate the Image

```bash
# Find the built image
ls tmp/deploy/images/ast2600-evb/

# Key files:
# - obmc-phosphor-image-ast2600-evb.static.mtd (flash image)
# - fitImage-obmc-phosphor-initramfs-ast2600-evb (kernel)
```

### Start QEMU

{: .note }
QEMU 6.0+ is required for ast2600-evb support. Check with `qemu-system-arm --version`.

```bash
# Run QEMU manually:
qemu-system-arm -m 1G \
    -M ast2600-evb \
    -nographic \
    -drive file=tmp/deploy/images/ast2600-evb/obmc-phosphor-image-ast2600-evb.static.mtd,format=raw,if=mtd \
    -net nic \
    -net user,hostfwd=tcp::2222-:22,hostfwd=tcp::2443-:443,hostfwd=udp::2623-:623
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
ls -la tmp/deploy/images/ast2600-evb/*.mtd
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

- [Development Workflow]({% link docs/01-getting-started/04-development-workflow.md %}) - Iterate quickly with devtool
- [OpenBMC Overview]({% link docs/02-architecture/01-openbmc-overview.md %}) - Understand the architecture
- [D-Bus Guide]({% link docs/02-architecture/02-dbus-guide.md %}) - Learn D-Bus communication
- [Sensor Guide]({% link docs/03-core-services/01-dbus-sensors-guide.md %}) - Configure sensors

---

{: .note }
**Tested on**: Ubuntu 22.04, OpenBMC master branch
