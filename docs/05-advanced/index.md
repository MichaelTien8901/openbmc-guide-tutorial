---
layout: default
title: Advanced Topics
nav_order: 6
has_children: true
permalink: /docs/advanced
---

# Advanced Topics

Dive into advanced protocols, security features, logging, and debug capabilities.

## What You'll Learn

- MCTP and PLDM for platform management (sensors, firmware update, BIOS config)
- SPDM for device attestation and security
- Secure boot and image signing
- Logging, diagnostics, and debug tools
- POST code monitoring and debug dump collection
- Firmware update mechanisms (BMC and BIOS/host firmware)
- Linux kernel and application debugging (sanitizers, Valgrind)
- eSPI communication (virtual wires, console, eDAF)
- Unit testing with GTest/GMock
- Integration testing with Robot Framework
- Linux kernel patching for driver development
- Multi-host BMC management
- Performance optimization for constrained BMC environments

## Topics

### Protocols & Security

Modern platform management relies on standardized protocols for component communication and security.

| Guide | Description | Difficulty |
|-------|-------------|------------|
| [MCTP/PLDM]({% link docs/05-advanced/01-mctp-pldm-guide.md %}) | Platform management protocols | Advanced |
| [PLDM Platform Monitoring]({% link docs/05-advanced/19-pldm-platform-monitoring-guide.md %}) | Type 2 sensors, PDRs, effecters, events | Advanced |
| [SPDM]({% link docs/05-advanced/02-spdm-guide.md %}) | Device attestation, security | Advanced |
| [Secure Boot & Signing]({% link docs/05-advanced/13-secure-boot-signing-guide.md %}) | Image signing, hardware root of trust | Advanced |

### Firmware Management

| Guide | Description |
|-------|-------------|
| [Firmware Update]({% link docs/05-advanced/03-firmware-update-guide.md %}) | BMC/PNOR updates, signing |
| [PLDM Firmware Update]({% link docs/05-advanced/20-pldm-firmware-update-guide.md %}) | Type 5 device firmware update via PLDM |
| [BIOS Firmware Management]({% link docs/05-advanced/16-bios-firmware-management-guide.md %}) | Host firmware update via BMC, BIOS config |

### Debug Features

Vendor-specific tools for deep system debugging.

| Guide | Description | Platform |
|-------|-------------|----------|
| [Intel ASD/ACD]({% link docs/05-advanced/04-intel-asd-acd-guide.md %}) | At-Scale Debug, Crash Dump, Error Injection | Intel |
| [AMD Debug & Management]({% link docs/05-advanced/05-amd-ihdt-guide.md %}) | APML, HDT, EPYC system management | AMD |

### Logging & Diagnostics

Capture events, errors, and diagnostic data for troubleshooting.

| Guide | Description |
|-------|-------------|
| [Logging]({% link docs/05-advanced/06-logging-guide.md %}) | Event logs, SEL, POST codes, debug dumps |
| [SDR]({% link docs/05-advanced/07-sdr-guide.md %}) | Sensor Data Records for IPMI |
| [Linux Debug Tools]({% link docs/05-advanced/08-linux-debug-tools-guide.md %}) | ASan, UBSan, TSan, Valgrind, KASAN |
| [Debug Dump Collection]({% link docs/05-advanced/17-debug-dump-collection-guide.md %}) | phosphor-debug-collector, dreport plugins |
| [POST Code Monitoring]({% link docs/05-advanced/18-post-code-monitoring-guide.md %}) | BIOS POST codes, boot progress tracking |

### Host Communication

Low-level interfaces for BMC-to-host communication.

| Guide | Description | Platform |
|-------|-------------|----------|
| [eSPI]({% link docs/05-advanced/09-espi-guide.md %}) | Virtual wires, console, eDAF boot | Intel/AMD |

### Testing

Validate code correctness with unit tests and system behavior with integration tests.

| Guide | Description | Scope |
|-------|-------------|-------|
| [Unit Testing]({% link docs/05-advanced/10-unit-testing-guide.md %}) | GTest/GMock for C++ unit tests | Single function/class |
| [Robot Framework]({% link docs/05-advanced/11-robot-framework-guide.md %}) | Integration testing with openbmc-test-automation | Full system behavior |

### Kernel & Driver Development

Modify the Linux kernel image for driver development and hardware enablement.

| Guide | Description | Difficulty |
|-------|-------------|------------|
| [Linux Kernel Patching]({% link docs/05-advanced/12-linux-kernel-patching-guide.md %}) | System patch files for driver development, device trees, kernel config | Advanced |

### Multi-Host & Platform Scaling

Manage multiple hosts from a single BMC and optimize for resource-constrained environments.

| Guide | Description | Difficulty |
|-------|-------------|------------|
| [Multi-Host Support]({% link docs/05-advanced/14-multi-host-support-guide.md %}) | Multi-host BMC management, instance routing | Advanced |
| [Performance Optimization]({% link docs/05-advanced/15-performance-optimization-guide.md %}) | Memory, startup, and I/O optimization | Advanced |

## Protocol Stack

```
┌─────────────────────────────────────────────────────────────┐
│                    Application Layer                        │
│  ┌─────────────┐  ┌──────────────┐  ┌─────────────────────┐ │
│  │    PLDM     │  │    SPDM      │  │   Vendor Specific   │ │
│  │  (Type 0-5) │  │ (Attestation)│  │   (ASD, APML)       │ │
│  └─────────────┘  └──────────────┘  └─────────────────────┘ │
├─────────────────────────────────────────────────────────────┤
│                    Transport Layer                          │
│  ┌─────────────────────────────────────────────────────────┐│
│  │                       MCTP                              ││
│  │            (Management Component Transport)             ││
│  └─────────────────────────────────────────────────────────┘│
├─────────────────────────────────────────────────────────────┤
│                    Physical Layer                           │
│  ┌───────────┐  ┌───────────┐  ┌───────────┐  ┌──────────┐  │
│  │  SMBus    │  │   PCIe    │  │    I3C    │  │   USB    │  │
│  └───────────┘  └───────────┘  └───────────┘  └──────────┘  │
└─────────────────────────────────────────────────────────────┘
```

## Prerequisites

- Strong understanding of [Architecture]({% link docs/02-architecture/index.md %})
- Familiarity with [Core Services]({% link docs/03-core-services/index.md %})
- Experience with [Interfaces]({% link docs/04-interfaces/index.md %})
- Knowledge of low-level hardware interfaces (I2C, PCIe)

{: .warning }
Advanced features often require specific hardware support. Check your platform capabilities before implementing.
