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
- Run and test in QEMU emulator
- Use the SDK for application development

## Prerequisites

- A Linux workstation (Ubuntu 20.04+ or Fedora 34+ recommended) OR Docker
- At least 16GB RAM (32GB recommended)
- 100GB+ free disk space
- Basic command line experience

## Guides in This Section

| Guide | Description | Time |
|-------|-------------|------|
| [Introduction]({% link docs/01-getting-started/01-introduction.md %}) | What is OpenBMC and why use it | 10 min |
| [Environment Setup]({% link docs/01-getting-started/02-environment-setup.md %}) | Set up your development environment | 30 min |
| [First Build]({% link docs/01-getting-started/03-first-build.md %}) | Build and run OpenBMC in QEMU | 45 min |

## Quick Path

If you're eager to get started:

1. **[Environment Setup]({% link docs/01-getting-started/02-environment-setup.md %})** - Get your tools ready
2. **[First Build]({% link docs/01-getting-started/03-first-build.md %})** - Build and run in QEMU
3. **[OpenBMC Overview]({% link docs/02-architecture/01-openbmc-overview.md %})** - Understand the architecture

{: .tip }
If you encounter issues, check the [Troubleshooting]({% link docs/01-getting-started/03-first-build.md %}#troubleshooting) section or search the [OpenBMC mailing list](https://lists.ozlabs.org/listinfo/openbmc).
