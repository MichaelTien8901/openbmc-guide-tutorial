---
layout: default
title: AMI OneTree vs OpenBMC
parent: Appendix
nav_order: 2
difficulty: beginner
prerequisites:
  - introduction
  - first-build
---

# AMI MegaRAC OneTree vs Upstream OpenBMC

## Overview

AMI [MegaRAC OneTree](https://www.ami.com/megarac/) is a commercial BMC firmware platform built on top of the open-source [OpenBMC](https://github.com/openbmc/openbmc) project. OneTree packages OpenBMC's open-source base with proprietary value-add modules, a unified multi-platform codebase, dedicated development tooling, and commercial support.

This appendix provides a technical comparison of the two platforms across build systems, development tools, testing, code architecture, and security.

## Relationship

```
┌──────────────────────────────────────────────────────────────┐
│                   AMI MegaRAC OneTree                         │
│  ┌────────────────────────────────────────────────────────┐  │
│  │          Proprietary Value-Add Modules                 │  │
│  │   GPU Mgmt · CXL Fabric · Liquid Cooling · Security   │  │
│  ├────────────────────────────────────────────────────────┤  │
│  │         OneTree Development Studio (ODS)               │  │
│  │        IDE · CLI · Project Wizard · SDK                │  │
│  ├────────────────────────────────────────────────────────┤  │
│  │              AMI Unified Codebase                      │  │
│  │   Multi-SoC · Multi-Platform · Curated Layers          │  │
│  ├────────────────────────────────────────────────────────┤  │
│  │            OpenBMC Open-Source Base                     │  │
│  │  Yocto · phosphor-* · bmcweb · sdbusplus · systemd    │  │
│  └────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────┘
```

AMI adopts an **"Open Source Base + Commercial Value-Added Modules"** strategy: the open base provides a standard framework for rapid deployment, while proprietary IP modules are selectable based on customer needs.

## Build System

| | OpenBMC | AMI OneTree |
|---|---|---|
| **Foundation** | Yocto / OpenEmbedded + BitBake | Same Yocto/BitBake underneath, abstracted by tooling |
| **Build command** | `bitbake obmc-phosphor-image` | OneTree Development Studio (ODS) GUI or CLI wraps BitBake |
| **Repo management** | `repo init` / `kas` to fetch 100+ individual git repos | Unified "OneTree" mono-repo managing multiple platforms in a single codebase |
| **Layers** | Community meta-layers (`meta-phosphor`, `meta-openembedded`, vendor layers like `meta-ibm`, `meta-facebook`) | AMI-curated layers + proprietary `meta-ami` layer |
| **Machine targets** | One machine config per vendor fork (e.g., `romulus`, `witherspoon`, `yosemite4`) | Multi-platform from one tree — ASPEED AST2500/2600/2700, Nuvoton Arbel |
| **Build reproducibility** | Depends on vendor pinning; community repos use rolling HEAD | Formal SDK releases (e.g., SDK v9.08) with pinned versions |

### OpenBMC Build Workflow

```bash
# Typical OpenBMC build
git clone https://github.com/openbmc/openbmc.git
cd openbmc

# Set up environment for a specific machine
. setup romulus

# Build the full image (can take 1-3 hours on first build)
bitbake obmc-phosphor-image
```

### OneTree Build Workflow

OneTree Development Studio provides a GUI-driven workflow for project creation, feature selection, and build configuration. Alternatively, the ODS CLI (v3.0) provides command-line access to the same capabilities for CI/CD integration.

> AMI explicitly markets OneTree as reducing the Yocto learning curve — developers interact with a higher-level abstraction rather than writing BitBake recipes directly.
{: .note }

## Development Tools & IDE

| | OpenBMC | AMI OneTree |
|---|---|---|
| **IDE** | No official IDE — use any editor (vim, VS Code, etc.) | **OneTree Development Studio (ODS)** — dedicated IDE with GUI for project creation, feature selection, platform config, and build |
| **CLI tooling** | Yocto `devtool` for recipe modification, `bitbake` directly | ODS CLI (v3.0) wraps build commands for streamlined workflows |
| **Recipe workflow** | Manual: `devtool modify`, `devtool add`, edit `.bb`/`.bbappend` files | GUI-driven feature selection and configuration, abstracts recipe-level details |
| **Learning curve** | Steep — requires understanding Yocto layers, BitBake syntax, recipe classes, `devtool`, OpenEmbedded | Reduced — ODS abstracts Yocto complexity |
| **SDK** | Yocto eSDK generated per build | Formal SDK releases (e.g., SDK v9.08) with unified kernel for AST2600, AST27x0, Arbel |

### OpenBMC devtool Workflow

```bash
# Modify an existing package source
devtool modify -n phosphor-logging /path/to/local/source

# Build the modified package
bitbake phosphor-logging

# Test in QEMU
runqemu romulus nographic

# Finish and generate patches
devtool finish phosphor-logging meta-phosphor
```

### OneTree Development Studio Features

- **Project creation wizard** — select SoC, platform, and feature set via GUI
- **Feature customization** — enable/disable BMC capabilities without editing recipes
- **Platform configuration** — configure hardware-specific settings
- **Build optimization** — managed build with dependency resolution
- **Firmware update tool** — integrated image deployment and update

## Testing & Emulation

| | OpenBMC | AMI OneTree |
|---|---|---|
| **QEMU** | Built-in QEMU machine models; Romulus is CI default | QEMU support inherited from OpenBMC; additional platform-specific configs |
| **CI system** | Jenkins at `jenkins.openbmc.org` — compiles commits, runs `make check` per repo, builds full image, runs Robot Framework in QEMU | Internal AMI QA pipeline with multiple QA cycles, third-party code scanning, in-house test suites |
| **Test framework** | Robot Framework (integration), GoogleTest/pytest (unit) | Same frameworks plus AMI proprietary test suites |
| **CI gating** | Two-tier: repo-level `make check` + system-level QEMU image tests | Multi-stage internal validation before release |

### OpenBMC CI Two-Tier Model

```
Tier 1: Repository-Level CI (fast, per-commit)
  └─ make check, unit tests, static analysis

Tier 2: System-Level CI (slower, full image)
  └─ bitbake full image → QEMU boot → Robot Framework tests
```

> OpenBMC CI runs automatically for org members. Non-member commits require a reviewer to manually trigger the CI run.
{: .note }

## Code Review & Contribution

| | OpenBMC | AMI OneTree |
|---|---|---|
| **Code hosting** | GitHub (source) + Gerrit (code review), per-repo | GitHub under [ocp-hm-openbmc-opf-ami](https://github.com/ocp-hm-openbmc-opf-ami/openbmc); internal review for proprietary code |
| **Review process** | Open Gerrit reviews with Jenkins CI gating | Internal AMI review for proprietary modules; upstream contributions follow OpenBMC Gerrit process |
| **Contribution model** | Fully open — anyone can submit patches | Dual: open-source base contributions go upstream; proprietary modules are AMI-internal |

## Code Architecture

Both platforms share the same core architecture since OneTree is built on OpenBMC:

| Component | OpenBMC | AMI OneTree |
|---|---|---|
| **Init system** | systemd | systemd |
| **IPC** | D-Bus (sdbusplus) | D-Bus (sdbusplus) |
| **Services** | `phosphor-*` daemons | `phosphor-*` + AMI proprietary extensions |
| **Web server** | `bmcweb` (Redfish) | `bmcweb` + AMI OEM Redfish schema extensions |
| **Package format** | `ipk` via `opkg` | `ipk` via `opkg` |
| **Protocols** | MCTP, PLDM, IPMI, Redfish | All of the above + SPDM, NVMe-MI, SMBPBI, CXL fabric management |

### OneTree Additional Capabilities

AMI adds proprietary modules for use cases beyond upstream OpenBMC:

- **Accelerator/GPU management** — monitor and manage GPGPUs
- **CXL fabric management** — memory expansion and pooling
- **Advanced liquid cooling management** — for high-density AI infrastructure
- **Enhanced telemetry** — extended RAS and real-time monitoring

## Silicon Support

| SoC | OpenBMC | AMI OneTree |
|---|---|---|
| ASPEED AST2500 | Supported (community) | Supported |
| ASPEED AST2600 | Supported (community) | Supported |
| ASPEED AST2700 | In progress (community) | Supported (unified kernel) |
| Nuvoton NPCM7xx | Supported (community) | Supported |
| Nuvoton Arbel | Limited | Supported (unified kernel) |

> OneTree's unified kernel approach means a single codebase supports AST2600, AST27x0, and Arbel, reducing porting effort across SoC families.
{: .tip }

## Security

| | OpenBMC | AMI OneTree |
|---|---|---|
| **Code scanning** | Community-driven; varies by vendor | Third-party scanning + in-house security test suites |
| **Secure boot** | Available but vendor-specific | Standardized secure boot across platforms |
| **Certifications** | None (community project) | OCP SAFE certified, ISO 9001:2015 |
| **Security audits** | Community review | Eclypsium identified OneTree as optimal among OpenBMC builds for security posture |

## Fragmentation: The Core Problem OneTree Solves

Upstream OpenBMC suffers from **fragmentation** — major vendors (Meta, Google, IBM, etc.) maintain separate forks with vendor-specific features in isolated repositories. This makes it difficult to:

- Share features across platforms
- Maintain a consistent security baseline
- Onboard new platforms without duplicating integration work

OneTree addresses this with a **unified mono-repo architecture** that manages multiple platforms, SoCs, and feature sets in a single codebase, while still tracking upstream OpenBMC.

```
OpenBMC Ecosystem (Fragmented):
  ├── openbmc/openbmc (upstream)
  ├── facebook/openbmc (Meta fork)
  ├── google/openbmc (Google fork)
  ├── IBM phosphor repos
  └── ...many vendor forks

AMI OneTree (Unified):
  └── OneTree mono-repo
       ├── OpenBMC upstream base
       ├── Multi-SoC platform support
       ├── AMI proprietary modules
       └── Customer customization layer
```

## Summary

| Aspect | OpenBMC | AMI OneTree |
|---|---|---|
| **Best for** | Hyperscalers with strong in-house firmware teams | ODMs/OEMs wanting faster time-to-market |
| **Flexibility** | Maximum — full control over everything | Reduced — abstractions trade flexibility for productivity |
| **Support** | Community (self-service) | Commercial (AMI global engineering) |
| **Cost** | Free (open source) | Commercial license |
| **Time-to-market** | Longer — must integrate everything yourself | Shorter — pre-integrated platform with tooling |

## References

- [AMI MegaRAC OneTree Product Page](https://www.ami.com/megarac/)
- [OneTree Development Studio Introduction](https://www.ami.com/blog/2025/03/04/introducing-onetree-development-studio-accelerating-openbmc-development-in-megarac-onetree/)
- [MegaRAC OneTree Version 3.0 Announcement](https://www.ami.com/resource/announcing-megarac-onetree-version-3-0/)
- [MegaRAC OneTree v2.1 Release](https://www.ami.com/blog/2025/08/20/ami-releases-megarac-onetree-2-1/)
- [Eclypsium OpenBMC Security Analysis](https://www.ami.com/blog/2025/06/19/eclypsium-examines-openbmc-security-across-multiple-builds-identifies-megarac-onetree-as-optimal-solution/)
- [AMI OneTree GitHub (OCP)](https://github.com/ocp-hm-openbmc-opf-ami/openbmc)
- [OpenBMC GitHub](https://github.com/openbmc/openbmc)
- [OpenBMC Yocto Development Docs](https://github.com/openbmc/docs/blob/master/yocto-development.md)
- [OpenBMC Development Guide](https://github.com/openbmc/docs/blob/master/development/README.md)
