---
layout: default
title: Learning Paths
nav_order: 1
description: "Curated reading sequences for different skill levels and roles"
permalink: /learning-paths
---

# Learning Paths
{: .no_toc }

Not sure where to start? Choose a learning path based on your experience level or role.
{: .fs-6 .fw-300 }

## Table of Contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

## Skill-Based Paths

Choose based on your OpenBMC experience level.

### Beginner Path

**For:** New to OpenBMC, want to understand fundamentals and get a working environment.

**Prerequisites:** Basic Linux command line, some C/C++ familiarity.

| # | Guide | What You'll Learn |
|---|-------|-------------------|
| 1 | [Introduction]({% link docs/01-getting-started/01-introduction.md %}) | What OpenBMC is and why it matters |
| 2 | [Environment Setup]({% link docs/01-getting-started/02-environment-setup.md %}) | Set up your development machine |
| 3 | [First Build]({% link docs/01-getting-started/03-first-build.md %}) | Build and run OpenBMC in QEMU |
| 4 | [OpenBMC Overview]({% link docs/02-architecture/01-openbmc-overview.md %}) | Understand the system architecture |
| 5 | [D-Bus Guide]({% link docs/02-architecture/02-dbus-guide.md %}) | Learn the core communication mechanism |
| 6 | [State Manager]({% link docs/02-architecture/03-state-manager-guide.md %}) | Understand BMC and host state management |

**Next Steps:** Continue to the Intermediate path, or explore Core Services based on your interests.

---

### Intermediate Path

**For:** Comfortable with OpenBMC basics, ready to work with core services and interfaces.

**Prerequisites:** Completed Beginner path or equivalent experience.

| # | Guide | What You'll Learn |
|---|-------|-------------------|
| 1 | [D-Bus Sensors]({% link docs/03-core-services/01-dbus-sensors-guide.md %}) | Expose sensor data via D-Bus |
| 2 | [Entity Manager]({% link docs/03-core-services/03-entity-manager-guide.md %}) | Dynamic hardware configuration |
| 3 | [Power Management]({% link docs/03-core-services/05-power-management-guide.md %}) | Control host power states |
| 4 | [Fan Control]({% link docs/03-core-services/04-fan-control-guide.md %}) | Thermal management and fan policies |
| 5 | [Redfish Guide]({% link docs/04-interfaces/02-redfish-guide.md %}) | Modern REST API for BMC management |
| 6 | [IPMI Guide]({% link docs/04-interfaces/01-ipmi-guide.md %}) | Legacy management interface |
| 7 | [Development Workflow]({% link docs/01-getting-started/04-development-workflow.md %}) | Iterate efficiently with devtool |

**Next Steps:** Continue to the Advanced path, or dive into specific interfaces and services.

---

### Advanced Path

**For:** Experienced OpenBMC developers ready for complex topics and platform porting.

**Prerequisites:** Solid understanding of D-Bus, services, and interfaces.

| # | Guide | What You'll Learn |
|---|-------|-------------------|
| 1 | [MCTP/PLDM Guide]({% link docs/05-advanced/01-mctp-pldm-guide.md %}) | Platform-level data model communication |
| 2 | [Firmware Update]({% link docs/05-advanced/03-firmware-update-guide.md %}) | BMC and host firmware update mechanisms |
| 3 | [Unit Testing]({% link docs/05-advanced/10-unit-testing-guide.md %}) | GTest/GMock for OpenBMC code |
| 4 | [Robot Framework]({% link docs/05-advanced/11-robot-framework-guide.md %}) | Integration and system testing |
| 5 | [Porting Reference]({% link docs/06-porting/01-porting-reference.md %}) | Complete platform porting guide |
| 6 | [Machine Layer]({% link docs/06-porting/02-machine-layer.md %}) | Create Yocto machine layer |
| 7 | [Device Tree]({% link docs/06-porting/03-device-tree.md %}) | Configure BMC hardware in DTS |

**Next Steps:** Explore specialized topics like SPDM, eSPI, or vendor-specific debug tools.

---

## Role-Based Paths

Choose based on your job function or project goals.

### Software Developer Path

**For:** Developers writing OpenBMC services, daemons, or applications.

**Focus:** D-Bus programming, service development, testing.

| # | Guide | What You'll Learn |
|---|-------|-------------------|
| 1 | [Environment Setup]({% link docs/01-getting-started/02-environment-setup.md %}) | Set up your development machine |
| 2 | [First Build]({% link docs/01-getting-started/03-first-build.md %}) | Build and run in QEMU |
| 3 | [D-Bus Guide]({% link docs/02-architecture/02-dbus-guide.md %}) | Core IPC mechanism |
| 4 | [D-Bus Sensors]({% link docs/03-core-services/01-dbus-sensors-guide.md %}) | Service implementation patterns |
| 5 | [Entity Manager]({% link docs/03-core-services/03-entity-manager-guide.md %}) | Configuration-driven services |
| 6 | [Development Workflow]({% link docs/01-getting-started/04-development-workflow.md %}) | Efficient iteration with devtool |
| 7 | [Unit Testing]({% link docs/05-advanced/10-unit-testing-guide.md %}) | GTest/GMock for your code |
| 8 | [Logging Guide]({% link docs/05-advanced/06-logging-guide.md %}) | phosphor-logging patterns |

---

### System Operator Path

**For:** Operators managing BMC-enabled servers, using IPMI/Redfish for administration.

**Focus:** Management interfaces, user management, network configuration.

| # | Guide | What You'll Learn |
|---|-------|-------------------|
| 1 | [Introduction]({% link docs/01-getting-started/01-introduction.md %}) | OpenBMC capabilities overview |
| 2 | [OpenBMC Overview]({% link docs/02-architecture/01-openbmc-overview.md %}) | System architecture |
| 3 | [IPMI Guide]({% link docs/04-interfaces/01-ipmi-guide.md %}) | ipmitool commands and operations |
| 4 | [Redfish Guide]({% link docs/04-interfaces/02-redfish-guide.md %}) | REST API for modern management |
| 5 | [WebUI Guide]({% link docs/04-interfaces/03-webui-guide.md %}) | Browser-based management |
| 6 | [User Manager]({% link docs/03-core-services/06-user-manager-guide.md %}) | User accounts and LDAP |
| 7 | [Network Guide]({% link docs/03-core-services/07-network-guide.md %}) | Network configuration |
| 8 | [Console Guide]({% link docs/04-interfaces/06-console-guide.md %}) | Serial-over-LAN access |

---

### Hardware Engineer Path

**For:** Engineers porting OpenBMC to new platforms or integrating BMC hardware.

**Focus:** Platform porting, device tree, hardware configuration.

| # | Guide | What You'll Learn |
|---|-------|-------------------|
| 1 | [Environment Setup]({% link docs/01-getting-started/02-environment-setup.md %}) | Development environment |
| 2 | [First Build]({% link docs/01-getting-started/03-first-build.md %}) | Build for reference platform |
| 3 | [Porting Reference]({% link docs/06-porting/01-porting-reference.md %}) | Complete porting overview |
| 4 | [Machine Layer]({% link docs/06-porting/02-machine-layer.md %}) | Yocto machine configuration |
| 5 | [Device Tree]({% link docs/06-porting/03-device-tree.md %}) | DTS for your hardware |
| 6 | [U-Boot]({% link docs/06-porting/04-uboot.md %}) | Bootloader customization |
| 7 | [Entity Manager Advanced]({% link docs/06-porting/07-entity-manager-advanced.md %}) | Hardware configuration files |
| 8 | [Verification]({% link docs/06-porting/05-verification.md %}) | Testing your port |

---

## Not Sure Which Path?

| If you want to... | Start with |
|-------------------|------------|
| Learn OpenBMC from scratch | [Beginner Path](#beginner-path) |
| Write OpenBMC code | [Software Developer Path](#software-developer-path) |
| Manage servers with BMC | [System Operator Path](#system-operator-path) |
| Port to new hardware | [Hardware Engineer Path](#hardware-engineer-path) |
| Understand a specific topic | Browse by [section](/docs/getting-started) |

---

{: .tip }
These paths are suggestions, not requirements. Feel free to skip guides you already know or explore topics in any order that suits your learning style.
