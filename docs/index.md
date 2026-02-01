---
layout: default
title: Home
nav_order: 1
description: "OpenBMC Guide Tutorial - Learn BMC development from beginner to professional"
permalink: /
---

# OpenBMC Guide Tutorial

Welcome to the comprehensive OpenBMC development guide. This tutorial takes you from beginner to professional, covering everything from environment setup to advanced platform porting.

## What You'll Learn

- **Getting Started**: Set up your development environment and build your first OpenBMC image
- **Architecture**: Understand OpenBMC's D-Bus architecture, services, and design patterns
- **Core Services**: Master sensors, thermal management, power control, and system services
- **Interfaces**: Implement IPMI, Redfish, WebUI, and other management interfaces
- **Advanced Topics**: Debug features, security protocols (SPDM), and specialized components
- **Platform Porting**: Port OpenBMC to your custom hardware

## Quick Start

1. [Set up your environment]({% link docs/01-getting-started/02-environment-setup.md %})
2. [Build your first image]({% link docs/01-getting-started/03-first-build.md %})
3. [Understand the architecture]({% link docs/02-architecture/01-openbmc-overview.md %})

## How This Guide is Organized

| Section | Description | Difficulty |
|---------|-------------|------------|
| [Getting Started]({% link docs/01-getting-started/index.md %}) | Environment setup, first build, QEMU testing | Beginner |
| [Architecture]({% link docs/02-architecture/index.md %}) | D-Bus, state management, core concepts | Beginner-Intermediate |
| [Core Services]({% link docs/03-core-services/index.md %}) | Sensors, thermal, power, logging | Intermediate |
| [Interfaces]({% link docs/04-interfaces/index.md %}) | IPMI, Redfish, WebUI, SSH | Intermediate |
| [Advanced]({% link docs/05-advanced/index.md %}) | MCTP/PLDM, SPDM, debug tools | Advanced |
| [Porting]({% link docs/06-porting/index.md %}) | Platform porting, device tree, verification | Advanced |

## Prerequisites

- Linux development experience (command line, build systems)
- Basic C/C++ programming knowledge
- Familiarity with embedded systems concepts (helpful but not required)

## Sample Code

All examples in this guide are tested and available in the [examples/](https://github.com/YOUR_ORG/openbmc-guide-tutorial/tree/main/examples) directory. Each example includes:

- Complete, buildable code
- README with setup instructions
- Verification steps for QEMU

## Contributing

Found an error? Want to add content? See our [Contributing Guide](CONTRIBUTING.md).

---

{: .note }
This guide is community-maintained and not officially affiliated with the OpenBMC project. For official documentation, visit [github.com/openbmc/docs](https://github.com/openbmc/docs).
