---
layout: default
title: Getting Started
nav_order: 2
has_children: true
permalink: /docs/getting-started
---

# Getting Started

This section covers everything you need to start developing with OpenBMC.

## What You'll Learn

- Set up a development environment on Linux, macOS, or Windows (via Docker)
- Clone and configure the OpenBMC repositories
- Build your first OpenBMC image
- Run and test in QEMU (the standard development environment)
- Use the SDK for application development

## No Hardware Required

{: .tip }
**QEMU is the standard development environment for OpenBMC** — not a compromise or simulation fallback. Professional OpenBMC developers at Google, Meta, IBM, and other companies use QEMU daily for most development work.

### Feature Comparison: QEMU vs Raspberry Pi vs Real Hardware

| Feature | QEMU (ASPEED) | Raspberry Pi | ASPEED AST2600 EVB |
|---------|---------------|--------------|---------------------|
| OpenBMC software stack | ✅ Full | ✅ Full | ✅ Full |
| D-Bus services | ✅ Full | ✅ Full | ✅ Full |
| Redfish API (bmcweb) | ✅ Full | ✅ Full | ✅ Full |
| Yocto/BitBake build | ✅ Full | ✅ Full | ✅ Full |
| I2C sensors (tmp105, EEPROMs) | ✅ Well emulated | ❌ No ASPEED I2C | ✅ Hardware |
| SPI flash (boot, firmware) | ✅ Well emulated | ❌ SD card boot | ✅ Hardware |
| GPIO (pins, interrupts) | ✅ Functional | ⚠️ Limited | ✅ Hardware |
| ADC (analog sensors) | ⚠️ Synthetic values | ❌ No built-in ADC | ✅ Hardware |
| IPMI KCS/BT interface | ⚠️ Partial | ❌ Not available | ✅ Hardware |
| PECI (CPU temperature) | ⚠️ Stub only | ❌ Not available | ✅ Hardware |
| PWM / fan tachometer | ⚠️ Register stub | ❌ Not available | ✅ Hardware |
| KVM-over-IP (video) | ❌ Not emulated | ❌ Not available | ✅ Hardware |
| eSPI host interface | ❌ Not emulated | ❌ Not available | ✅ Hardware |
| Secure Boot (RoT) | ⚠️ Basic OTP only | ❌ Not available | ✅ Hardware |
| **Cost** | **Free** | **$35-75** | **$500-800** |

### What Requires Real Hardware

Only specialized hardware bring-up tasks need physical BMC hardware:

- KVM-over-IP video capture and encoding
- eSPI/LPC host interface debugging
- PECI CPU temperature monitoring with real data
- Real fan control with PWM and tachometer feedback
- Real analog sensor calibration
- Platform-specific GPIO timing

These topics are relevant only for hardware engineers doing board bring-up — not for learning OpenBMC software development.

### Recommendation

| Option | Cost | Best For |
|--------|------|----------|
| **QEMU** | Free | ✅ Learning and software development — start here |
| Raspberry Pi | $35-75 | ⚠️ Exploring the software stack on real hardware, but no BMC peripherals |
| ASPEED AST2600 EVB | $500-800 | Full hardware bring-up and production development |

## Prerequisites

- A Linux workstation (Ubuntu 22.04+ or Fedora 38+ recommended) OR Docker
- At least 16GB RAM (32GB recommended)
- 100GB+ free disk space
- Basic command line experience

## Guides in This Section

| Guide | Description | Time |
|-------|-------------|------|
| [Introduction]({% link docs/01-getting-started/01-introduction.md %}) | What is OpenBMC and why use it | 10 min |
| [Environment Setup]({% link docs/01-getting-started/02-environment-setup.md %}) | Set up your development environment | 30 min |
| [First Build]({% link docs/01-getting-started/03-first-build.md %}) | Build and run OpenBMC in QEMU | 45 min |
| [Development Workflow]({% link docs/01-getting-started/04-development-workflow.md %}) | Iterate quickly with devtool and bbappend | 30 min |
| [Building QEMU]({% link docs/01-getting-started/05-qemu-build.md %}) | Build QEMU from source if needed | 20 min |
| [Devtool Workflow]({% link docs/01-getting-started/06-devtool-workflow-guide.md %}) | Advanced devtool usage for recipe development | 30 min |
| [Gerrit Contribution]({% link docs/01-getting-started/07-gerrit-contribution-guide.md %}) | Submit patches to OpenBMC via Gerrit | 30 min |

## Quick Path

If you're eager to get started:

1. **[Environment Setup]({% link docs/01-getting-started/02-environment-setup.md %})** - Get your tools ready
2. **[First Build]({% link docs/01-getting-started/03-first-build.md %})** - Build and run in QEMU
3. **[OpenBMC Overview]({% link docs/02-architecture/01-openbmc-overview.md %})** - Understand the architecture

{: .tip }
If you encounter issues, check the [Troubleshooting]({% link docs/01-getting-started/03-first-build.md %}#troubleshooting) section or search the [OpenBMC mailing list](https://lists.ozlabs.org/listinfo/openbmc).
