---
layout: default
title: Linux Kernel Patching
parent: Advanced Topics
nav_order: 12
difficulty: advanced
prerequisites:
  - environment-setup
  - first-build
  - machine-layer
  - device-tree
---

# Linux Kernel Patching for Driver Development
{: .no_toc }

Modify the Linux kernel image in OpenBMC using system patch files for driver development, bug fixes, and hardware enablement.
{: .fs-6 .fw-300 }

## Table of Contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

## Overview

When developing or modifying drivers for OpenBMC, you often need to patch the Linux kernel image itself. Unlike userspace services that live in separate recipes, kernel changes — new drivers, bug fixes, device tree modifications, or configuration changes — require a structured patching workflow through Yocto/BitBake.

OpenBMC maintains its own kernel tree at [openbmc/linux](https://github.com/openbmc/linux) with a development branch naming convention of `dev-X.Y` (e.g., `dev-6.18`). The kernel recipe pins to a specific commit hash for reproducibility, and your patches are applied on top during the build.

**Key concepts covered:**
- How OpenBMC organizes kernel recipes across meta-layers
- Two workflows for kernel patching: `devtool` (interactive) and `bbappend` (permanent)
- Creating and applying kernel configuration fragments
- Device tree patching for new hardware
- Testing kernel changes on QEMU before flashing hardware
- Best practices for upstreaming patches

{: .warning }
Kernel patches directly affect system stability. Always test on QEMU before deploying to hardware. A bad kernel patch can brick a BMC, requiring physical recovery.

---

## How OpenBMC Structures Kernel Recipes

Understanding the layer hierarchy helps you know where to place your patches.

### Layer Hierarchy

```
┌─────────────────────────────────────────────────────────┐
│  Platform/Vendor Layer  (meta-ibm, meta-google, etc.)   │
│  ── Machine-specific patches + config fragments         │
├─────────────────────────────────────────────────────────┤
│  Distribution Layer  (meta-phosphor)                    │
│  ── Phosphor-specific kernel configs (GPIO, etc.)       │
├─────────────────────────────────────────────────────────┤
│  BSP Layer  (meta-aspeed, meta-nuvoton)                 │
│  ── Base kernel recipe, SoC defconfig, kernel source    │
└─────────────────────────────────────────────────────────┘
```

Each layer adds its own `.bbappend` files and config fragments on top of the base recipe. The build system merges them in layer priority order.

### Key Files in meta-aspeed

| File | Purpose |
|------|---------|
| `recipes-kernel/linux/linux-aspeed_git.bb` | Pins kernel branch, version, and commit hash |
| `recipes-kernel/linux/linux-aspeed.inc` | SRC_URI, license, build settings, conditional features |
| `recipes-kernel/linux/linux-aspeed/aspeed-g4/defconfig` | AST2400 (ARMv5) base kernel config |
| `recipes-kernel/linux/linux-aspeed/aspeed-g5/defconfig` | AST2500 (ARMv6) base kernel config |
| `recipes-kernel/linux/linux-aspeed/aspeed-g6/defconfig` | AST2600 (ARMv7) base kernel config |

### The Base Kernel Recipe

The `linux-aspeed_git.bb` recipe is minimal — it pins the source and delegates to the include:

```bitbake
KBRANCH ?= "dev-6.18"
LINUX_VERSION ?= "6.18.8"
SRCREV = "3fcb5927beef6fc8d9faa16b90c01fc6e67f2065"

require linux-aspeed.inc
```

The include file (`linux-aspeed.inc`) sets up the source fetch, defconfig selection, and conditional features:

```bitbake
KSRC ?= "git://github.com/openbmc/linux;protocol=https;branch=${KBRANCH}"
SRC_URI = "${KSRC}"
SRC_URI += "file://defconfig"

# Conditional: TPM2 support
SRC_URI += "${@bb.utils.contains('MACHINE_FEATURES', 'tpm2', 'file://tpm2.cfg', '', d)}"

# Conditional: UBI filesystem
SRC_URI += "${@bb.utils.contains('DISTRO_FEATURES', 'ubi', 'file://ubi.cfg', '', d)}"

KCONFIG_MODE = "--alldefconfig"
inherit kernel linux-yocto
```

---

## Workflow 1: devtool (Interactive Development)

Use `devtool` when you are actively developing a kernel change — editing code, testing iteratively, and refining before committing. This is the recommended workflow for driver development.

### Step-by-Step

```bash
# 1. Source the OpenBMC build environment for your machine
cd openbmc
. setup romulus

# 2. Check out the kernel source into a workspace
devtool modify linux-aspeed
```

This clones the kernel into `build/workspace/sources/linux-aspeed/` and sets up BitBake to build from your local checkout instead of the cached source.

```bash
# 3. Navigate to the kernel source
cd build/workspace/sources/linux-aspeed

# 4. Make your driver changes
vim drivers/hwmon/my_sensor.c
vim drivers/hwmon/Makefile
vim drivers/hwmon/Kconfig

# 5. Commit your changes (REQUIRED — uncommitted changes are ignored!)
git add drivers/hwmon/my_sensor.c drivers/hwmon/Makefile drivers/hwmon/Kconfig
git commit -s -m "hwmon: my_sensor: Add support for XYZ sensor chip"
```

{: .warning }
You **must** commit your changes to git. The `devtool` workflow ignores uncommitted modifications in the working tree.

```bash
# 6. Build just the kernel to test compilation
devtool build linux-aspeed

# 7. Or build the full image
bitbake obmc-phosphor-image

# 8. When satisfied, export patches to your meta-layer
devtool finish linux-aspeed ~/openbmc/meta-mymachine

# OR create just a bbappend without removing the workspace
devtool update-recipe -a ~/openbmc/meta-mymachine linux-aspeed

# 9. Clean up the workspace when done
devtool reset linux-aspeed
```

### Interactive Kernel Configuration

Use `menuconfig` to explore and change kernel options interactively:

```bash
# Open the ncurses-based config editor
bitbake linux-aspeed -c menuconfig

# After saving, generate a defconfig
bitbake linux-aspeed -c savedefconfig
```

{: .note }
The `devtool modify` command checks out the branch specified in the recipe (e.g., `dev-6.18`). Unlike some recipes, it does **not** create a separate `devtool` branch — patches are applied directly on the checked-out branch.

---

## Workflow 2: bbappend with Patch Files (Permanent Integration)

Use this approach when you have a finalized patch ready to integrate into your machine layer. This is the standard method for production systems.

### Creating Patch Files

Generate patches from your kernel git tree using `git format-patch`:

```bash
# Single patch from the last commit
git format-patch -1

# Multiple patches from the last 3 commits
git format-patch -3

# Patches since branching from a base
git format-patch origin/dev-6.18..HEAD
```

This produces numbered patch files like `0001-hwmon-my_sensor-Add-support-for-XYZ.patch`.

### Directory Structure

Place patches in your meta-layer following this convention:

```
meta-vendor/
  meta-platform/
    recipes-kernel/
      linux/
        linux-aspeed_%.bbappend          # The append file
        linux-aspeed/                     # Directory matching recipe name
          my-platform.cfg                 # Config fragment
          0001-hwmon-add-xyz-driver.patch # Kernel source patch
          0002-dts-add-platform.patch     # Device tree patch
```

### Writing the bbappend

Create `linux-aspeed_%.bbappend` (the `%` wildcard matches any version):

```bitbake
FILESEXTRAPATHS:prepend := "${THISDIR}/${PN}:"

SRC_URI += " \
    file://0001-hwmon-add-xyz-driver.patch \
    file://0002-dts-add-platform.patch \
    file://my-platform.cfg \
"
```

The `FILESEXTRAPATHS:prepend` line tells BitBake to search the `linux-aspeed/` subdirectory (matching `${PN}`) alongside the append file for the referenced files.

### Real-World Example: Vesnin Platform

From `meta-yadro/meta-vesnin`:

```bitbake
FILESEXTRAPATHS:prepend := "${THISDIR}/${PN}:"
SRC_URI:append:vesnin = " \
    file://vesnin.cfg \
    file://0002-vesnin-remap-aspeed-uart.patch \
"
```

This adds a UART remapping patch and a platform-specific config fragment, but only for the `vesnin` machine.

### Patch Application Order

{: .note }
Patches listed in `SRC_URI` with `file://` are **not guaranteed** to apply in the order listed. To enforce ordering, use a `.scc` (Series Configuration Control) file:

```
# my-patches.scc
patch 0001-first-fix.patch
patch 0002-second-fix.patch
patch 0003-third-fix.patch
```

Then reference the `.scc` file in `SRC_URI` instead of individual patches.

---

## Kernel Configuration Fragments

Rather than maintaining a complete defconfig (thousands of lines), use **configuration fragments** — small `.cfg` files containing only the options you need to change.

### Creating Fragments

**Method 1: diffconfig (recommended)**

```bash
# Start from a clean config
bitbake linux-aspeed -c kernel_configme -f

# Make changes interactively
bitbake linux-aspeed -c menuconfig

# Generate a fragment of just your changes
bitbake linux-aspeed -c diffconfig
# Output: fragment.cfg in the kernel work directory
```

**Method 2: Manual creation**

```bash
cat > my-driver.cfg << 'EOF'
CONFIG_I2C_SLAVE=y
CONFIG_SENSORS_LM75=y
CONFIG_SENSORS_TMP421=m
# CONFIG_SENSORS_FAKE is not set
EOF
```

### Applying Fragments

Add the fragment via your `.bbappend`:

```bitbake
FILESEXTRAPATHS:prepend := "${THISDIR}/${PN}:"
SRC_URI += "file://my-driver.cfg"
```

### Validating Configuration

Verify that all fragment options were applied correctly:

```bash
bitbake linux-aspeed -c kernel_configcheck -f
```

This produces warnings when a requested option does not appear in the final `.config`, helping you catch silent configuration failures.

{: .tip }
Start `.cfg` files with a blank line — some Yocto versions silently skip the first line. The `KCONFIG_MODE = "--alldefconfig"` setting in `linux-aspeed.inc` means any option not explicitly set gets its default value.

---

## Device Tree Patching

Device trees describe hardware to the kernel. For a new platform or hardware modification, you often need to add or patch a device tree source (DTS) file.

### DTS Naming Convention

OpenBMC follows the upstream Linux convention:

```
aspeed-bmc-<vendor>-<platform>.dts
```

Examples: `aspeed-bmc-opp-romulus.dts`, `aspeed-bmc-ibm-rainier.dts`, `aspeed-bmc-amd-onyx.dts`

All DTS files live in `arch/arm/boot/dts/aspeed/` in the kernel tree and include base SoC definitions:

| SoC | Include | Generation |
|-----|---------|------------|
| AST2400 | `aspeed-g4.dtsi` | G4 (ARMv5) |
| AST2500 | `aspeed-g5.dtsi` | G5 (ARMv6) |
| AST2600 | `aspeed-g6.dtsi` | G6 (ARMv7) |

### Creating a New Device Tree

```dts
// SPDX-License-Identifier: GPL-2.0-or-later
// aspeed-bmc-vendor-platform.dts
/dts-v1/;

#include "aspeed-g6.dtsi"
#include <dt-bindings/gpio/aspeed-gpio.h>
#include <dt-bindings/leds/common.h>

/ {
    model = "Vendor Platform BMC";
    compatible = "vendor,platform-bmc", "aspeed,ast2600";

    chosen {
        stdout-path = &uart5;
        bootargs = "console=ttyS4,115200n8 root=/dev/ram rw";
    };

    leds {
        compatible = "gpio-leds";
        fault {
            gpios = <&gpio ASPEED_GPIO(N, 2) GPIO_ACTIVE_LOW>;
        };
    };
};

&i2c0 {
    status = "okay";

    temperature-sensor@48 {
        compatible = "ti,tmp175";
        reg = <0x48>;
    };
};

&uart5 {
    status = "okay";
};
```

### Adding DTS to the Build

Two files need changes:

1. Add to the kernel Makefile (`arch/arm/boot/dts/aspeed/Makefile`):
   ```makefile
   dtb-$(CONFIG_ARCH_ASPEED) += aspeed-bmc-vendor-platform.dtb
   ```

2. Set in your machine configuration:
   ```bitbake
   KERNEL_DEVICETREE = "aspeed-bmc-vendor-platform.dtb"
   ```

### Patching an Existing Device Tree

Generate a patch, then add it via `.bbappend`:

```bash
# In the kernel tree
git add arch/arm/boot/dts/aspeed/aspeed-bmc-vendor-platform.dts
git add arch/arm/boot/dts/aspeed/Makefile
git commit -s -m "ARM: dts: aspeed: Add Vendor Platform BMC device tree"
git format-patch -1
```

```bitbake
# linux-aspeed_%.bbappend
FILESEXTRAPATHS:prepend := "${THISDIR}/${PN}:"
SRC_URI += "file://0001-ARM-dts-aspeed-Add-Vendor-Platform-BMC-device-tree.patch"
```

{: .note }
Device tree source files are an **exception** to the upstream-first rule in OpenBMC. You can carry DTS patches in your meta-layer without waiting for upstream acceptance. However, you should still aim to upstream them eventually.

---

## Testing Kernel Changes

### QEMU Testing

Always validate kernel patches on QEMU before deploying to hardware:

```bash
# Build the full image with your kernel changes
bitbake obmc-phosphor-image

# Boot with QEMU
qemu-system-arm -M ast2600-evb \
  -drive file=tmp/deploy/images/ast2600-evb/flash-ast2600-evb,format=raw,if=mtd \
  -nographic
```

Or boot kernel and DTB separately:

```bash
qemu-system-arm -M ast2600-evb \
  -kernel tmp/deploy/images/ast2600-evb/zImage \
  -dtb tmp/deploy/images/ast2600-evb/aspeed-bmc-vendor-platform.dtb \
  -initrd tmp/deploy/images/ast2600-evb/obmc-phosphor-initramfs-ast2600-evb.cpio.gz \
  -nographic
```

### TFTP Netboot (Without Reflashing)

For faster iteration, serve the kernel image over TFTP instead of reflashing:

```bash
# Copy FIT image to TFTP server
cp tmp/deploy/images/<machine>/fitImage /tftpboot/

# In U-Boot console on the BMC:
setenv ipaddr 192.168.0.80
setenv serverip 192.168.0.11
tftp 0x83000000 fitImage
bootm 0x83000000
```

{: .tip }
Use `0x43000000` for AST2400 boards. Use `0x83000000` for AST2500/AST2600. This address is the kernel load address in DRAM.

### Out-of-Tree Kernel Build

For the fastest compile-test cycle, build the kernel outside of BitBake entirely:

```bash
# Configure for AST2600
make ARCH=arm O=obj CROSS_COMPILE=arm-linux-gnueabihf- aspeed_g6_defconfig

# Build
make ARCH=arm O=obj CROSS_COMPILE=arm-linux-gnueabihf- -j$(nproc)

# Build with initramfs baked in
make ARCH=arm O=obj CROSS_COMPILE=arm-linux-gnueabihf- \
  CONFIG_INITRAMFS_SOURCE=/path/to/obmc-phosphor-image-<machine>.cpio.gz
```

{: .note }
The cross-compiler (`arm-linux-gnueabihf-`) is available from your Yocto SDK or your distribution's `gcc-arm-linux-gnueabihf` package.

---

## Verifying Your Patches

After building, verify that your changes took effect.

### Check Kernel Version and Patches

```bash
# On the running BMC
uname -a
cat /proc/version
```

### Verify Driver is Loaded

```bash
# Check if your driver module is loaded
lsmod | grep my_driver

# Check kernel ring buffer for driver messages
dmesg | grep my_driver

# Check device tree nodes
ls /proc/device-tree/
cat /proc/device-tree/compatible
```

### Verify Kernel Config

```bash
# If /proc/config.gz is enabled
zcat /proc/config.gz | grep CONFIG_MY_OPTION
```

### BitBake Validation

```bash
# Verify config fragments were applied
bitbake linux-aspeed -c kernel_configcheck -f

# Verify patch application succeeded
bitbake linux-aspeed -c patch
```

---

## Common Patch Scenarios

### Scenario 1: Adding a New hwmon Driver

A new temperature sensor on the I2C bus needs a kernel driver.

1. Add driver source to `drivers/hwmon/` and update `Kconfig`/`Makefile`
2. Add the device node to your platform DTS
3. Create a config fragment enabling the driver
4. Package as patches in your meta-layer

```
meta-vendor/recipes-kernel/linux/
  linux-aspeed_%.bbappend
  linux-aspeed/
    0001-hwmon-add-xyz-sensor-driver.patch     # Driver code
    0002-dts-add-xyz-sensor-to-platform.patch   # DTS node
    enable-xyz-sensor.cfg                       # CONFIG_SENSORS_XYZ=y
```

### Scenario 2: Fixing an Existing Driver Bug

A known upstream fix hasn't been backported to the OpenBMC kernel branch yet.

```bash
# Cherry-pick from upstream Linux
cd build/workspace/sources/linux-aspeed
git cherry-pick <upstream-commit-hash>

# If it doesn't apply cleanly, resolve conflicts and commit
git add -u
git commit -s

# Export the patch
git format-patch -1
```

### Scenario 3: Enabling a Kernel Subsystem

You need USB gadget support that is disabled by default.

```bash
# Create a config fragment
cat > usb-gadget.cfg << 'EOF'

CONFIG_USB_GADGET=y
CONFIG_USB_CONFIGFS=y
CONFIG_USB_CONFIGFS_MASS_STORAGE=y
EOF
```

No kernel source patches needed — just the `.cfg` fragment and a `.bbappend`.

---

## Upstreaming Best Practices

### OpenBMC Upstream-First Policy

The OpenBMC kernel tree's development policy is **"code must be upstream first."** Code enters the OpenBMC kernel in order of preference:

1. **Upstream release integration** — arrives automatically when OpenBMC advances kernel versions
2. **Backporting** — cherry-picking accepted upstream commits to the current OpenBMC branch
3. **Temporary carry patches** — held in the OpenBMC tree while upstream review is ongoing (least preferred)

### Commit Message Format

Follow the Linux kernel commit message conventions:

```
subsystem: component: Short description (under 50 chars)

Detailed explanation of the change. Explain the problem being solved
and why this approach was chosen. Wrap at 72 characters.

Tested on ast2600-evb QEMU and physical hardware.

Signed-off-by: Your Name <your.email@example.com>
```

### Submission to Upstream Linux

```bash
# Format patches for upstream
git format-patch -1 --cc=openbmc@lists.ozlabs.org

# Send via email to the subsystem maintainer
git send-email --to=maintainer@kernel.org \
  --cc=openbmc@lists.ozlabs.org \
  0001-my-patch.patch
```

### Submission to OpenBMC Kernel Tree

For patches carried temporarily in the OpenBMC tree:

```bash
git format-patch \
  --subject-prefix="PATCH linux dev-6.18" \
  --to=openbmc@lists.ozlabs.org \
  -1
```

Push to Gerrit for code review:

```bash
git push gerrit HEAD:refs/for/dev-6.18
```

---

## Troubleshooting

### Issue: Patch Fails to Apply

**Symptom**: BitBake errors with "Patch failed" during `do_patch`

**Cause**: The patch was generated against a different kernel version or conflicts with other patches in the layer stack.

**Solution**:
1. Check the base commit your patch was generated from
2. Use `devtool modify linux-aspeed` to get the exact source BitBake uses
3. Regenerate the patch against that source:
   ```bash
   cd build/workspace/sources/linux-aspeed
   # Apply your changes, commit, then:
   git format-patch -1
   ```

### Issue: Config Option Not Taking Effect

**Symptom**: Your `.cfg` fragment sets `CONFIG_MY_OPTION=y` but the final `.config` has it unset

**Cause**: A dependency is missing, or another config overrides yours.

**Solution**:
1. Run `bitbake linux-aspeed -c kernel_configcheck -f` to see warnings
2. Check dependencies in `menuconfig` — the option may require a parent option
3. Add the parent option to your fragment as well

### Issue: devtool modify Uses Wrong defconfig

**Symptom**: After `devtool modify`, the kernel builds with an incorrect or minimal config

**Cause**: Known issue ([openbmc/openbmc#3294](https://github.com/openbmc/openbmc/issues/3294)) where devtool may not apply machine-specific defconfig correctly.

**Solution**:
1. Manually copy the correct defconfig:
   ```bash
   cp meta-aspeed/recipes-kernel/linux/linux-aspeed/aspeed-g6/defconfig \
     build/workspace/sources/linux-aspeed/.config
   ```
2. Or use the bbappend workflow instead of devtool for the final integration

### Issue: Kernel Boots But Driver Not Found

**Symptom**: `modprobe my_driver` returns "Module not found" or device is not detected at boot

**Cause**: Driver not enabled in kernel config, or device tree node missing/incorrect.

**Solution**:
1. Verify config: `zcat /proc/config.gz | grep MY_DRIVER`
2. Verify DTS node: `ls /proc/device-tree/soc/...`
3. Check `dmesg` for probe failures: `dmesg | grep -i error`

---

## Quick Reference

### Essential Commands

| Task | Command |
|------|---------|
| Check out kernel for editing | `devtool modify linux-aspeed` |
| Build kernel only | `devtool build linux-aspeed` |
| Interactive config editor | `bitbake linux-aspeed -c menuconfig` |
| Generate config diff | `bitbake linux-aspeed -c diffconfig` |
| Validate config fragments | `bitbake linux-aspeed -c kernel_configcheck -f` |
| Save current config as defconfig | `bitbake linux-aspeed -c savedefconfig` |
| Export patches to layer | `devtool finish linux-aspeed ~/meta-mylayer` |
| Clean up workspace | `devtool reset linux-aspeed` |
| Force re-patch | `bitbake linux-aspeed -c patch -f` |
| Full rebuild from scratch | `bitbake linux-aspeed -c cleansstate && bitbake linux-aspeed` |

### Patch Workflow Summary

```
┌──────────────────────────────────────────────────────────────────┐
│                    Development Phase                             │
│                                                                  │
│  devtool modify ──> Edit source ──> git commit ──> devtool build │
│       │                                                │         │
│       │            Iterate until working               │         │
│       └────────────────────────────────────────────────┘         │
├──────────────────────────────────────────────────────────────────┤
│                    Integration Phase                             │
│                                                                  │
│  git format-patch ──> Place in meta-layer ──> Write .bbappend    │
│                                                                  │
│  OR: devtool finish linux-aspeed ~/meta-mylayer                  │
├──────────────────────────────────────────────────────────────────┤
│                    Validation Phase                              │
│                                                                  │
│  bitbake obmc-phosphor-image ──> QEMU test ──> Hardware test     │
├──────────────────────────────────────────────────────────────────┤
│                    Upstream Phase                                │
│                                                                  │
│  git send-email (upstream) ──> Gerrit push (OpenBMC tree)        │
└──────────────────────────────────────────────────────────────────┘
```

---

## References

- [OpenBMC Kernel Development Guide](https://github.com/openbmc/docs/blob/master/kernel-development.md) — official kernel development policy and workflow
- [OpenBMC Yocto Development](https://github.com/openbmc/docs/blob/master/yocto-development.md) — devtool workflow for OpenBMC
- [OpenBMC Cheatsheet](https://github.com/openbmc/docs/blob/master/cheatsheet.md) — quick reference for devtool, BitBake, and TFTP testing
- [OpenBMC Add New System](https://github.com/openbmc/docs/blob/master/development/add-new-system.md) — adding platforms with DTS and kernel config
- [Yocto Kernel Development Manual](https://docs.yoctoproject.org/kernel-dev/common.html) — devtool, patches, and config fragments
- [Yocto devtool Reference](https://docs.yoctoproject.org/ref-manual/devtool-reference.html) — complete devtool command reference
- [Linux Kernel Submitting Patches](https://www.kernel.org/doc/Documentation/process/submitting-patches.rst) — upstream kernel submission guide
- [OpenBMC Linux Kernel Repository](https://github.com/openbmc/linux) — kernel source tree
