---
layout: default
title: Advanced
nav_order: 5
has_children: true
permalink: /docs/advanced
---

# Advanced Topics

Dive into advanced protocols, security features, logging, and debug capabilities.

## What You'll Learn

- MCTP and PLDM for platform management
- SPDM for device attestation and security
- Logging, diagnostics, and debug tools
- Firmware update mechanisms
- Linux kernel and application debugging (sanitizers, Valgrind)
- eSPI communication (virtual wires, console, eDAF)

## Topics

### Protocols & Security

Modern platform management relies on standardized protocols for component communication and security.

| Guide | Description | Difficulty |
|-------|-------------|------------|
| [MCTP/PLDM]({% link docs/05-advanced/01-mctp-pldm-guide.md %}) | Platform management protocols | Advanced |
| [SPDM]({% link docs/05-advanced/02-spdm-guide.md %}) | Device attestation, security | Advanced |

### Firmware Management

| Guide | Description |
|-------|-------------|
| [Firmware Update]({% link docs/05-advanced/03-firmware-update-guide.md %}) | BMC/PNOR updates, signing |

### Debug Features

Vendor-specific tools for deep system debugging.

| Guide | Description | Platform |
|-------|-------------|----------|
| [Intel ASD/ACD]({% link docs/05-advanced/04-intel-asd-acd-guide.md %}) | At-Scale Debug, Crash Dump | Intel |
| [AMD Debug & Management]({% link docs/05-advanced/05-amd-ihdt-guide.md %}) | APML, HDT, EPYC system management | AMD |

### Logging & Diagnostics

Capture events, errors, and diagnostic data for troubleshooting.

| Guide | Description |
|-------|-------------|
| [Logging]({% link docs/05-advanced/06-logging-guide.md %}) | Event logs, SEL, POST codes, debug dumps |
| [SDR]({% link docs/05-advanced/07-sdr-guide.md %}) | Sensor Data Records for IPMI |
| [Linux Debug Tools]({% link docs/05-advanced/08-linux-debug-tools-guide.md %}) | ASan, UBSan, TSan, Valgrind, KASAN |

### Host Communication

Low-level interfaces for BMC-to-host communication.

| Guide | Description | Platform |
|-------|-------------|----------|
| [eSPI]({% link docs/05-advanced/09-espi-guide.md %}) | Virtual wires, console, eDAF boot | Intel/AMD |

## Protocol Stack

```
┌─────────────────────────────────────────────────────────────┐
│                    Application Layer                         │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐  │
│  │    PLDM     │  │    SPDM     │  │   Vendor Specific   │  │
│  │  (Type 0-5) │  │ (Attestation)│  │   (ASD, APML)       │  │
│  └─────────────┘  └─────────────┘  └─────────────────────┘  │
├─────────────────────────────────────────────────────────────┤
│                    Transport Layer                           │
│  ┌─────────────────────────────────────────────────────────┐│
│  │                       MCTP                               ││
│  │            (Management Component Transport)              ││
│  └─────────────────────────────────────────────────────────┘│
├─────────────────────────────────────────────────────────────┤
│                    Physical Layer                            │
│  ┌───────────┐  ┌───────────┐  ┌───────────┐  ┌──────────┐ │
│  │  SMBus    │  │   PCIe    │  │    I3C    │  │   USB    │ │
│  └───────────┘  └───────────┘  └───────────┘  └──────────┘ │
└─────────────────────────────────────────────────────────────┘
```

## Prerequisites

- Strong understanding of [Architecture]({% link docs/02-architecture/index.md %})
- Familiarity with [Core Services]({% link docs/03-core-services/index.md %})
- Experience with [Interfaces]({% link docs/04-interfaces/index.md %})
- Knowledge of low-level hardware interfaces (I2C, PCIe)

{: .warning }
Advanced features often require specific hardware support. Check your platform capabilities before implementing.
