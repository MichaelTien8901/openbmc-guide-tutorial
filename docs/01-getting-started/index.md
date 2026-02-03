---
layout: default
title: Getting Started
nav_order: 1
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

### Why QEMU is the Right Choice

| What QEMU Provides | Coverage |
|-------------------|----------|
| Full OpenBMC software stack | ✅ 100% |
| D-Bus architecture and all services | ✅ 100% |
| Redfish API (bmcweb) | ✅ 100% |
| IPMI interface (ipmitool works) | ✅ 100% |
| Yocto/BitBake build system | ✅ 100% |
| Code modification and testing | ✅ 100% |
| Sensor/fan/power state management | ✅ Simulated |

### What Requires Real Hardware

Only specialized hardware bring-up tasks need physical BMC hardware:

- eSPI/LPC host interface debugging
- PECI CPU communication
- Real sensor calibration
- Platform-specific GPIO timing

These topics are relevant only for hardware engineers doing board bring-up — not for learning OpenBMC software development.

### Hardware Cost Reality

| Option | Cost | Practicality |
|--------|------|--------------|
| **QEMU** | Free | ✅ Best for learning and development |
| ASPEED AST2600 EVB | $500-800 | ❌ Too expensive for most |
| Raspberry Pi | $35-75 | ❌ Cannot run OpenBMC (wrong SoC) |

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

## Quick Path

If you're eager to get started:

1. **[Environment Setup]({% link docs/01-getting-started/02-environment-setup.md %})** - Get your tools ready
2. **[First Build]({% link docs/01-getting-started/03-first-build.md %})** - Build and run in QEMU
3. **[OpenBMC Overview]({% link docs/02-architecture/01-openbmc-overview.md %})** - Understand the architecture

{: .tip }
If you encounter issues, check the [Troubleshooting]({% link docs/01-getting-started/03-first-build.md %}#troubleshooting) section or search the [OpenBMC mailing list](https://lists.ozlabs.org/listinfo/openbmc).
