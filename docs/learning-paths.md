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
| 7 | [Systemd Boot Ordering]({% link docs/02-architecture/05-systemd-boot-ordering-guide.md %}) | How services start and depend on each other |

**Next Steps:** Continue to the Intermediate path, or explore Core Services based on your interests.

---

### Intermediate Path

**For:** Comfortable with OpenBMC basics, ready to work with core services and interfaces.

**Prerequisites:** Completed Beginner path or equivalent experience.

| # | Guide | What You'll Learn |
|---|-------|-------------------|
| 1 | [D-Bus Sensors]({% link docs/03-core-services/01-dbus-sensors-guide.md %}) | Expose sensor data via D-Bus |
| 2 | [Entity Manager]({% link docs/03-core-services/03-entity-manager-guide.md %}) | Dynamic hardware configuration |
| 3 | [GPIO Management]({% link docs/03-core-services/14-gpio-management-guide.md %}) | Monitor and control GPIO signals |
| 4 | [I2C Device Integration]({% link docs/03-core-services/16-i2c-device-integration-guide.md %}) | Add I2C devices to device tree |
| 5 | [Power Management]({% link docs/03-core-services/05-power-management-guide.md %}) | Control host power states |
| 6 | [Fan Control]({% link docs/03-core-services/04-fan-control-guide.md %}) | Thermal management and fan policies |
| 7 | [Redfish Guide]({% link docs/04-interfaces/02-redfish-guide.md %}) | Modern REST API for BMC management |
| 8 | [IPMI Guide]({% link docs/04-interfaces/01-ipmi-guide.md %}) | Legacy management interface |
| 9 | [Devtool Workflow]({% link docs/01-getting-started/06-devtool-workflow-guide.md %}) | Advanced recipe development with devtool |

**Next Steps:** Continue to the Advanced path, or dive into specific interfaces and services.

---

### Advanced Path

**For:** Experienced OpenBMC developers ready for complex topics and platform porting.

**Prerequisites:** Solid understanding of D-Bus, services, and interfaces.

| # | Guide | What You'll Learn |
|---|-------|-------------------|
| 1 | [MCTP/PLDM Guide]({% link docs/05-advanced/01-mctp-pldm-guide.md %}) | Platform-level data model communication |
| 2 | [Firmware Update]({% link docs/05-advanced/03-firmware-update-guide.md %}) | BMC and host firmware update mechanisms |
| 3 | [Secure Boot & Signing]({% link docs/05-advanced/13-secure-boot-signing-guide.md %}) | Image signing and hardware root of trust |
| 4 | [Unit Testing]({% link docs/05-advanced/10-unit-testing-guide.md %}) | GTest/GMock for OpenBMC code |
| 5 | [Robot Framework]({% link docs/05-advanced/11-robot-framework-guide.md %}) | Integration and system testing |
| 6 | [Performance Optimization]({% link docs/05-advanced/15-performance-optimization-guide.md %}) | Optimize for constrained BMC environments |
| 7 | [Porting Reference]({% link docs/06-porting/01-porting-reference.md %}) | Complete platform porting guide |
| 8 | [Machine Layer]({% link docs/06-porting/02-machine-layer.md %}) | Create Yocto machine layer |
| 9 | [Device Tree]({% link docs/06-porting/03-device-tree.md %}) | Configure BMC hardware in DTS |

**Next Steps:** Explore specialized topics like SPDM, eSPI, multi-host, or vendor-specific debug tools.

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
| 4 | [Custom D-Bus Services]({% link docs/02-architecture/04-custom-dbus-services-guide.md %}) | Build your own D-Bus service with sdbus++ |
| 5 | [D-Bus Sensors]({% link docs/03-core-services/01-dbus-sensors-guide.md %}) | Service implementation patterns |
| 6 | [Entity Manager]({% link docs/03-core-services/03-entity-manager-guide.md %}) | Configuration-driven services |
| 7 | [Devtool Workflow]({% link docs/01-getting-started/06-devtool-workflow-guide.md %}) | Advanced recipe development with devtool |
| 8 | [Unit Testing]({% link docs/05-advanced/10-unit-testing-guide.md %}) | GTest/GMock for your code |
| 9 | [Logging Guide]({% link docs/05-advanced/06-logging-guide.md %}) | phosphor-logging patterns |
| 10 | [Gerrit Contribution]({% link docs/01-getting-started/07-gerrit-contribution-guide.md %}) | Submit patches upstream via Gerrit |

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
| 5 | [Redfish Events & Telemetry]({% link docs/04-interfaces/08-redfish-events-telemetry-guide.md %}) | Event subscriptions and metric reports |
| 6 | [WebUI Guide]({% link docs/04-interfaces/03-webui-guide.md %}) | Browser-based management |
| 7 | [User Manager]({% link docs/03-core-services/06-user-manager-guide.md %}) | User accounts and LDAP |
| 8 | [LDAP Integration]({% link docs/03-core-services/18-ldap-integration-guide.md %}) | LDAP/Active Directory authentication |
| 9 | [Network Guide]({% link docs/03-core-services/07-network-guide.md %}) | Network configuration |
| 10 | [Console Guide]({% link docs/04-interfaces/06-console-guide.md %}) | Serial-over-LAN access |

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
| 6 | [I2C Device Integration]({% link docs/03-core-services/16-i2c-device-integration-guide.md %}) | Add I2C devices and drivers |
| 7 | [Flash Layout Optimization]({% link docs/06-porting/08-flash-layout-optimization-guide.md %}) | SPI flash partitioning and image sizing |
| 8 | [U-Boot]({% link docs/06-porting/04-uboot.md %}) | Bootloader customization |
| 9 | [Entity Manager Advanced]({% link docs/06-porting/07-entity-manager-advanced.md %}) | Hardware configuration files |
| 10 | [Verification]({% link docs/06-porting/05-verification.md %}) | Testing your port |

---

### RAS / Validation Engineer Path

**For:** Engineers validating platform reliability, error handling, and crash dump mechanisms.

**Focus:** Error injection, crash dump analysis, POST code monitoring, debug tools.

| # | Guide | What You'll Learn |
|---|-------|-------------------|
| 1 | [Environment Setup]({% link docs/01-getting-started/02-environment-setup.md %}) | Development environment |
| 2 | [OpenBMC Overview]({% link docs/02-architecture/01-openbmc-overview.md %}) | System architecture |
| 3 | [PECI Thermal Monitoring]({% link docs/03-core-services/15-peci-thermal-monitoring-guide.md %}) | CPU thermal interface and PECI commands |
| 4 | [Intel ASD/ACD]({% link docs/05-advanced/04-intel-asd-acd-guide.md %}) | Debug access, crash dumps, error injection |
| 5 | [Debug Dump Collection]({% link docs/05-advanced/17-debug-dump-collection-guide.md %}) | BMC diagnostic dump collection |
| 6 | [POST Code Monitoring]({% link docs/05-advanced/18-post-code-monitoring-guide.md %}) | Boot progress tracking and diagnostics |
| 7 | [Logging Guide]({% link docs/05-advanced/06-logging-guide.md %}) | Event logs and SEL entries |
| 8 | [Robot Framework]({% link docs/05-advanced/11-robot-framework-guide.md %}) | Automated RAS test suites |

---

### Security Engineer Path

**For:** Engineers implementing and validating BMC security features.

**Focus:** Secure boot, image signing, authentication, attestation.

| # | Guide | What You'll Learn |
|---|-------|-------------------|
| 1 | [Environment Setup]({% link docs/01-getting-started/02-environment-setup.md %}) | Development environment |
| 2 | [OpenBMC Overview]({% link docs/02-architecture/01-openbmc-overview.md %}) | System architecture |
| 3 | [Secure Boot & Signing]({% link docs/05-advanced/13-secure-boot-signing-guide.md %}) | Image signing and hardware root of trust |
| 4 | [SPDM Guide]({% link docs/05-advanced/02-spdm-guide.md %}) | Device attestation and measurement |
| 5 | [Certificate Manager]({% link docs/03-core-services/09-certificate-manager-guide.md %}) | TLS/SSL certificate management |
| 6 | [User Manager]({% link docs/03-core-services/06-user-manager-guide.md %}) | Accounts and privilege roles |
| 7 | [LDAP Integration]({% link docs/03-core-services/18-ldap-integration-guide.md %}) | Enterprise directory authentication |
| 8 | [SSH Security]({% link docs/04-interfaces/07-ssh-security-guide.md %}) | SSH hardening and access control |

---

## Not Sure Which Path?

| If you want to... | Start with |
|-------------------|------------|
| Learn OpenBMC from scratch | [Beginner Path](#beginner-path) |
| Write OpenBMC code | [Software Developer Path](#software-developer-path) |
| Manage servers with BMC | [System Operator Path](#system-operator-path) |
| Port to new hardware | [Hardware Engineer Path](#hardware-engineer-path) |
| Validate RAS / error handling | [RAS / Validation Engineer Path](#ras--validation-engineer-path) |
| Implement BMC security | [Security Engineer Path](#security-engineer-path) |
| Understand a specific topic | Browse by [section](/docs/getting-started) |

---

{: .tip }
These paths are suggestions, not requirements. Feel free to skip guides you already know or explore topics in any order that suits your learning style.
