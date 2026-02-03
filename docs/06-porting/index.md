---
layout: default
title: Porting
nav_order: 7
has_children: true
permalink: /docs/porting
---

# Platform Porting

Port OpenBMC to your custom hardware platform.

## What You'll Learn

- Create a machine-specific layer
- Configure device tree for your BMC SoC
- Set up U-Boot for your platform
- Enable and configure OpenBMC services
- Verify and validate your port
- Port to ARM-based server platforms (NVIDIA, Ampere)

## Porting Overview

```
┌─────────────────────────────────────────────────────────────┐
│                    Your Machine Layer                       │
│                   meta-<your-company>                       │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────┐  │
│  │ Machine Config  │  │  Device Tree    │  │   Recipes   │  │
│  │   <machine>.conf│  │   <soc>.dts     │  │   *.bb      │  │
│  └─────────────────┘  └─────────────────┘  └─────────────┘  │
├─────────────────────────────────────────────────────────────┤
│                    Phosphor Layer                           │
│                     meta-phosphor                           │
├─────────────────────────────────────────────────────────────┤
│                    OpenBMC Distro                           │
│                     meta-openbmc                            │
├─────────────────────────────────────────────────────────────┤
│                    Yocto/Poky                               │
│           meta-poky, meta-oe, meta-networking               │
└─────────────────────────────────────────────────────────────┘
```

## Porting Workflow

1. **Plan** - Identify hardware, map features to OpenBMC services
2. **Create Layer** - Set up meta-<your-machine> structure
3. **Device Tree** - Configure BMC SoC peripherals
4. **U-Boot** - Configure bootloader
5. **Enable Services** - Configure OpenBMC features
6. **Test** - Verify each feature works
7. **Iterate** - Fix issues, add features

## Guides in This Section

| Guide                                                                   | Description           | Phase         |
|-------------------------------------------------------------------------|-----------------------|---------------|
| [Porting Reference]({% link docs/06-porting/01-porting-reference.md %}) | Complete checklist    | Planning      |
| [Machine Layer]({% link docs/06-porting/02-machine-layer.md %})         | Create your layer     | Setup         |
| [Device Tree]({% link docs/06-porting/03-device-tree.md %})             | BMC SoC configuration | Configuration |
| [U-Boot]({% link docs/06-porting/04-uboot.md %})                        | Bootloader setup      | Configuration |
| [Verification]({% link docs/06-porting/05-verification.md %})           | Testing procedures    | Validation    |
| [ARM Platform Guide]({% link docs/06-porting/06-arm-platform-guide.md %}) | ARM server platforms | Advanced      |
| [Entity Manager Advanced]({% link docs/06-porting/07-entity-manager-advanced.md %}) | Dynamic hardware config | Advanced |

## Supported BMC SoCs

OpenBMC supports several BMC system-on-chip platforms:

| SoC     | Vendor  | Common Platforms      |
|---------|---------|-----------------------|
| AST2400 | ASPEED  | Legacy systems        |
| AST2500 | ASPEED  | Current mainstream    |
| AST2600 | ASPEED  | Latest generation     |
| NPCM7xx | Nuvoton | Alternative platforms |

{: .note }
For ARM-based server platforms (NVIDIA Grace, Ampere, etc.), see the [ARM Platform Guide]({% link docs/06-porting/06-arm-platform-guide.md %}).

## Prerequisites

- Complete all previous sections
- Strong Linux kernel knowledge
- Device tree experience
- Yocto/BitBake proficiency
- Access to your target hardware

{: .important }
Porting requires hardware access. While some testing can be done in QEMU, final validation needs real hardware.

## Getting Help

- [OpenBMC Mailing List](https://lists.ozlabs.org/listinfo/openbmc)
- [OpenBMC Discord](https://discord.gg/openbmc)
- Review existing machine layers in the OpenBMC repository
