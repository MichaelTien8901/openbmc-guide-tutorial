---
layout: default
title: Linux Kernel Driver Development
parent: Advanced Topics
nav_order: 12
difficulty: advanced
prerequisites:
  - environment-setup
  - first-build
  - machine-layer
  - device-tree
---

# Linux Kernel Driver Development
{: .no_toc }

Develop, debug, and integrate Linux kernel drivers for OpenBMC — from kernel patching and out-of-tree modules to userspace alternatives and end-to-end sensor binding.
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
- Building out-of-tree kernel modules as standalone Yocto recipes
- Userspace driver alternatives (libgpiod, i2c-dev, spidev, UIO)
- Driver debugging techniques (dynamic_debug, ftrace, debugfs)
- End-to-end I2C/SPI sensor binding walkthrough
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

## Out-of-Tree Kernel Modules

When your driver does not belong in the upstream kernel tree — vendor-specific hardware, proprietary logic, or rapid prototyping — build it as an **out-of-tree kernel module**. This keeps your driver in its own Yocto recipe, decoupled from the kernel source and build cycle.

### When to Use Out-of-Tree vs In-Tree

| Factor | Out-of-Tree Module | In-Tree Patch |
|--------|--------------------|---------------|
| Upstream acceptance | Not planned or not possible | Planned or already accepted |
| Build coupling | Independent recipe, faster rebuilds | Tied to full kernel rebuild |
| Development speed | Fast iteration — rebuild only your module | Slower — full kernel compile on change |
| Kernel API stability | Must track API changes across kernel versions | Automatically consistent |
| Deployment | Can be updated independently of kernel | Requires full firmware image update |

{: .tip }
For most BMC production drivers, prefer in-tree patches (upstream-first policy). Use out-of-tree modules for vendor-specific hardware abstraction layers, debug/test modules, or drivers still in active prototyping.

### Recipe Layout in Your Meta-Layer

```
meta-vendor/
  meta-platform/
    recipes-kernel/
      my-hwmon-module/
        my-hwmon-module_1.0.bb           # Yocto recipe
        files/
          Makefile                         # Kbuild Makefile
          my_hwmon_driver.c               # Module source
          my-hwmon-module.conf            # Autoload config
```

### Kbuild Makefile

The out-of-tree module Makefile uses standard Kbuild syntax:

```makefile
# files/Makefile
obj-m := my_hwmon_driver.o
```

For multi-file modules:

```makefile
obj-m := my_hwmon_driver.o
my_hwmon_driver-objs := main.o i2c_ops.o sysfs_attrs.o
```

### Module Source (Minimal Example)

```c
// files/my_hwmon_driver.c
#include <linux/module.h>
#include <linux/i2c.h>
#include <linux/hwmon.h>

static int my_hwmon_probe(struct i2c_client *client)
{
    dev_info(&client->dev, "my_hwmon_driver probed at 0x%02x\n", client->addr);
    return 0;
}

static const struct of_device_id my_hwmon_of_match[] = {
    { .compatible = "vendor,my-sensor" },
    { }
};
MODULE_DEVICE_TABLE(of, my_hwmon_of_match);

static struct i2c_driver my_hwmon_driver = {
    .driver = {
        .name = "my-hwmon-driver",
        .of_match_table = my_hwmon_of_match,
    },
    .probe = my_hwmon_probe,
};
module_i2c_driver(my_hwmon_driver);

MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("Example out-of-tree hwmon driver for BMC");
```

### Yocto Recipe Using module.bbclass

```bitbake
# my-hwmon-module_1.0.bb
SUMMARY = "Out-of-tree hwmon driver for vendor sensor"
LICENSE = "GPL-2.0-only"
LIC_FILES_CHKSUM = "file://my_hwmon_driver.c;beginline=1;endline=1;md5=..."

SRC_URI = " \
    file://Makefile \
    file://my_hwmon_driver.c \
    file://my-hwmon-module.conf \
"

S = "${WORKDIR}"

inherit module

# Autoload at boot
KERNEL_MODULE_AUTOLOAD += "my_hwmon_driver"

# Install autoload config
do_install:append() {
    install -d ${D}${sysconfdir}/modules-load.d
    install -m 0644 ${WORKDIR}/my-hwmon-module.conf \
        ${D}${sysconfdir}/modules-load.d/
}
```

The `inherit module` line pulls in `module.bbclass`, which handles cross-compilation against the kernel headers, module signing (if enabled), and packaging into the correct `/lib/modules/<version>/` directory.

### Module Autoloading

Create a `.conf` file for `/etc/modules-load.d/`:

```bash
# files/my-hwmon-module.conf
# Load vendor hwmon driver at boot
my_hwmon_driver
```

Alternatively, use `KERNEL_MODULE_AUTOLOAD` in the recipe (shown above) which writes the appropriate config automatically.

### Building and Testing

```bash
# Build just the module recipe
bitbake my-hwmon-module

# Build the full image (includes the module)
bitbake obmc-phosphor-image

# On the running BMC, verify the module
lsmod | grep my_hwmon
modinfo my_hwmon_driver
```

---

## Userspace Driver Alternatives

Not every hardware interaction requires a kernel driver. For simple register reads, GPIO toggling, or I2C device testing, userspace access is faster to develop and easier to debug. This section helps you decide when a userspace approach is sufficient.

### Decision Framework: Kernel Driver vs Userspace

| Criterion | Kernel Driver | Userspace Access |
|-----------|---------------|------------------|
| **Interrupt handling** | Required — only kernel can register IRQ handlers | Not possible (polling only) |
| **Latency requirements** | Microsecond-level response | Millisecond-level acceptable |
| **Shared device access** | Kernel manages arbitration | Single process at a time |
| **DMA support** | Full DMA engine access | Not available |
| **Upstream acceptance** | Required for OpenBMC mainline | Not applicable — stays in your layer |
| **Development speed** | Slower (compile, deploy, reboot) | Fast (edit, run) |
| **Debugging** | Kernel oops, printk, ftrace | gdb, printf, strace |
| **hwmon/D-Bus integration** | Automatic via hwmon subsystem | Manual — must write your own bridge |

{: .note }
If your device needs to appear as a standard hwmon sensor on D-Bus (for dbus-sensors/entity-manager integration), you almost always need a kernel driver. Userspace approaches are best for prototyping, diagnostics, and one-off access.

### libgpiod — GPIO Access

libgpiod v2 is the recommended way to access GPIO lines from userspace. It replaces the deprecated sysfs GPIO interface (`/sys/class/gpio/`).

**Command-line tools:**

```bash
# List all GPIO chips
gpiodetect

# Show lines on a specific chip
gpioinfo gpiochip0

# Read a GPIO line value
gpioget gpiochip0 42

# Set a GPIO line (active-high)
gpioset gpiochip0 42=1

# Monitor a line for events (rising/falling edge)
gpiomon gpiochip0 42
```

**C API snippet:**

```c
#include <gpiod.h>

struct gpiod_chip *chip = gpiod_chip_open("/dev/gpiochip0");
struct gpiod_line_settings *settings = gpiod_line_settings_new();
gpiod_line_settings_set_direction(settings, GPIOD_LINE_DIRECTION_INPUT);

struct gpiod_line_config *config = gpiod_line_config_new();
static const unsigned int offset = 42;
gpiod_line_config_add_line_settings(config, &offset, 1, settings);

struct gpiod_line_request *request =
    gpiod_chip_request_lines(chip, NULL, config);

enum gpiod_line_value value =
    gpiod_line_request_get_value(request, offset);

gpiod_line_request_release(request);
gpiod_line_config_free(config);
gpiod_line_settings_free(settings);
gpiod_chip_close(chip);
```

{: .tip }
OpenBMC uses libgpiod extensively in `phosphor-gpio-monitor` and `phosphor-buttons`. See the [GPIO Management Guide]({% link docs/03-core-services/14-gpio-management-guide.md %}) for the full OpenBMC GPIO architecture.

### i2c-dev / i2c-tools — Direct I2C Access

The `i2c-dev` kernel module exposes I2C buses as `/dev/i2c-N` character devices.

```bash
# List I2C buses
i2cdetect -l

# Scan for devices on bus 0
i2cdetect -y 0

# Read a register (bus 0, device 0x48, register 0x00)
i2cget -y 0 0x48 0x00 w

# Write a register
i2cset -y 0 0x48 0x01 0x60 w

# Dump all registers
i2cdump -y 0 0x48
```

{: .warning }
Using `i2c-tools` on a bus where a kernel driver is already bound can cause bus contention and unpredictable behavior. Use `i2cdetect` to check if addresses show `UU` (already claimed by a driver).

### spidev — SPI Userspace Access

The `spidev` driver exposes SPI devices as `/dev/spidevB.C` (bus B, chip-select C).

Device tree binding:

```dts
&spi1 {
    status = "okay";

    spidev@0 {
        compatible = "linux,spidev";
        reg = <0>;
        spi-max-frequency = <10000000>;
    };
};
```

```bash
# Test SPI communication (requires spi-tools package)
spi-config -d /dev/spidev1.0 -q
spi-pipe -d /dev/spidev1.0 -s 1000000 < data.bin > response.bin
```

### UIO — Userspace I/O for Register-Mapped Devices

UIO maps device registers directly into userspace memory, allowing you to write a full driver without kernel code. Useful for FPGA registers or vendor-specific control blocks.

Device tree binding:

```dts
my-device@1e6e0000 {
    compatible = "generic-uio";
    reg = <0x1e6e0000 0x1000>;
};
```

Kernel config fragment:

```
CONFIG_UIO=y
CONFIG_UIO_PDRV_GENIRQ=y
```

Userspace access:

```c
#include <sys/mman.h>
#include <fcntl.h>

int fd = open("/dev/uio0", O_RDWR);
void *regs = mmap(NULL, 0x1000, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);

uint32_t val = ((volatile uint32_t *)regs)[0];  // Read register 0x00
((volatile uint32_t *)regs)[1] = 0xDEADBEEF;    // Write register 0x04

munmap(regs, 0x1000);
close(fd);
```

### /dev/mem and devmem2 — Direct Physical Memory Access

For quick register checks during debugging, `devmem2` reads and writes physical addresses directly.

```bash
# Read SCU register on AST2600 (Silicon Revision)
devmem2 0x1e6e2004 w

# Write a register
devmem2 0x1e6e2000 w 0x1688A8A8
```

{: .warning }
`/dev/mem` access bypasses all kernel protections. A wrong write can corrupt memory, hang the SoC, or brick the BMC. Use only for debugging on development systems. Production firmware should disable `/dev/mem` access (`CONFIG_STRICT_DEVMEM=y`).

---

## Driver Debugging

Debugging kernel drivers on a BMC is constrained: limited flash storage rules out large trace buffers, there is typically no JTAG/kgdb access, and the BMC may be the only management interface to the system. These techniques work within those constraints.

### dynamic_debug — Runtime Debug Prints

The `dynamic_debug` facility lets you enable `dev_dbg()` and `pr_debug()` messages at runtime without rebuilding the kernel. This is the single most useful driver debugging tool on a BMC.

**Enable for a specific module:**

```bash
# Enable all debug prints in the lm75 driver
echo "module lm75 +p" > /sys/kernel/debug/dynamic_debug/control

# Enable for a specific file
echo "file drivers/hwmon/lm75.c +p" > /sys/kernel/debug/dynamic_debug/control

# Enable for a specific function
echo "func lm75_probe +p" > /sys/kernel/debug/dynamic_debug/control

# Include function name and line number in output
echo "module lm75 +pflm" > /sys/kernel/debug/dynamic_debug/control
```

**Flags:** `p` = print, `f` = function name, `l` = line number, `m` = module name, `t` = thread ID

**View output:**

```bash
dmesg -w  # Follow kernel log in real time
```

**Kernel config required:**

```
CONFIG_DYNAMIC_DEBUG=y
```

{: .tip }
To enable debug messages early in boot (before userspace is up), add `dyndbg="module lm75 +p"` to the kernel command line in U-Boot or the device tree `chosen` node.

### ftrace — Probe Sequence Tracing

Use `ftrace` with the `function_graph` tracer to visualize the call chain during driver probe — invaluable for understanding why a probe fails or hangs.

```bash
# Enable function_graph tracer
echo function_graph > /sys/kernel/debug/tracing/current_tracer

# Filter to your driver's functions
echo "lm75_*" > /sys/kernel/debug/tracing/set_ftrace_filter

# Or trace the entire I2C subsystem
echo "i2c_*" >> /sys/kernel/debug/tracing/set_ftrace_filter

# Start tracing
echo 1 > /sys/kernel/debug/tracing/tracing_on

# Trigger a probe (rebind the driver)
echo "0-0048" > /sys/bus/i2c/drivers/lm75/unbind
echo "0-0048" > /sys/bus/i2c/drivers/lm75/bind

# Stop and read the trace
echo 0 > /sys/kernel/debug/tracing/tracing_on
cat /sys/kernel/debug/tracing/trace
```

**Example output:**

```
 1)               |  lm75_probe() {
 1)   0.834 us    |    devm_regmap_init_i2c();
 1)   0.417 us    |    regmap_read();
 1)               |    devm_hwmon_device_register_with_info() {
 1)   1.250 us    |      hwmon_device_register_with_info();
 1)   1.667 us    |    }
 1)   4.584 us    |  }
```

{: .note }
On memory-constrained BMCs, reduce the trace buffer: `echo 512 > /sys/kernel/debug/tracing/buffer_size_kb` (default is often 1408 KB per CPU).

### debugfs Interfaces

Several kernel subsystems expose debugging information through debugfs:

**GPIO state:**

```bash
cat /sys/kernel/debug/gpio
# Shows all registered GPIO chips, claimed lines, direction, and value
```

**I2C bus information:**

```bash
# If CONFIG_I2C_DEBUG_CORE is enabled
ls /sys/kernel/debug/i2c/
```

**Regmap register dumps:**

```bash
# If your driver uses regmap, its registers are exposed automatically
cat /sys/kernel/debug/regmap/0-0048/registers
```

**Clock tree (useful for SoC debugging):**

```bash
cat /sys/kernel/debug/clk/clk_summary
```

### dmesg Patterns for Common Probe Failures

When a driver fails to probe, `dmesg` contains the clues. Here are the patterns to look for:

**Missing device tree node:**

```
# No output at all for your driver — it was never matched
# Check: does your DTS node have the right compatible string?
cat /proc/device-tree/soc/apb/bus@1e78a000/i2c-bus@100/temperature-sensor@48/compatible
```

**Wrong compatible string:**

```
# Driver loads but never probes — compatible mismatch
# Compare driver's of_match_table with DTS compatible
cat /sys/bus/i2c/drivers/lm75/module/drivers
```

**Deferred probe:**

```
lm75 0-0048: probe deferral - supplier not ready
# A dependency (regulator, clock, GPIO) isn't available yet
# Check: cat /sys/kernel/debug/devices_deferred
```

**I2C communication failure:**

```
lm75 0-0048: Failed to read register 0x00: -6
# -6 = ENXIO (no device at that address)
# Verify with: i2cdetect -y 0
```

**Missing kernel config:**

```
# modprobe: FATAL: Module lm75 not found
# Check: zcat /proc/config.gz | grep LM75
```

---

## I2C/SPI Sensor Binding Walkthrough

This end-to-end walkthrough traces the full path for adding an I2C hwmon sensor to an OpenBMC system, from device tree to Redfish visibility. We use the **TI TMP175** temperature sensor as the running example — it is supported by the `lm75` kernel driver and works in QEMU.

```
┌──────────┐    ┌──────────┐    ┌──────────┐    ┌───────────────┐    ┌─────────────┐    ┌─────────┐
│ Device   │───>│ Kernel   │───>│ hwmon    │───>│ Entity        │───>│ dbus-       │───>│ Redfish │
│ Tree     │    │ Driver   │    │ sysfs    │    │ Manager       │    │ sensors     │    │         │
│ Node     │    │ Binding  │    │ Interface│    │ JSON Config   │    │ D-Bus Expose│    │ Sensor  │
└──────────┘    └──────────┘    └──────────┘    └───────────────┘    └─────────────┘    └─────────┘
```

### Step 1: Device Tree Node

Add the sensor to your platform's device tree on the appropriate I2C bus:

```dts
&i2c0 {
    status = "okay";

    temperature-sensor@48 {
        compatible = "ti,tmp175";
        reg = <0x48>;
    };
};
```

Key fields:
- **`compatible`**: Must match a string in the kernel driver's `of_device_id` table. For TMP175, the `lm75` driver matches `"ti,tmp175"`.
- **`reg`**: The 7-bit I2C address. TMP175 defaults to `0x48` (A0=A1=A2=GND).
- **Node name**: Convention is `<function>@<addr>`, e.g., `temperature-sensor@48`.

### Step 2: Kernel Driver Binding

The kernel's I2C subsystem matches the DTS `compatible` string against registered drivers. For TMP175:

```
Driver: drivers/hwmon/lm75.c
Compatible table entry: { .compatible = "ti,tmp175", .data = &tmp175 }
```

At boot, when the I2C bus is initialized, the kernel:
1. Parses the DTS node and creates an `i2c_client` for address `0x48`
2. Matches `"ti,tmp175"` to the `lm75` driver
3. Calls `lm75_probe()`, which reads chip ID registers and creates an hwmon device

Verify binding succeeded:

```bash
# Check driver bound to device
ls -la /sys/bus/i2c/devices/0-0048/driver
# Should show: ... -> ../../../bus/i2c/drivers/lm75

# Check dmesg for probe
dmesg | grep lm75
# lm75 0-0048: hwmon0: sensor 'tmp175'
```

### Step 3: hwmon sysfs Verification

Once the driver probes successfully, it exposes temperature readings through the hwmon sysfs interface:

```bash
# Find the hwmon device
ls /sys/class/hwmon/
# hwmon0

# Check which driver owns it
cat /sys/class/hwmon/hwmon0/name
# tmp175

# Read temperature (in millidegrees Celsius)
cat /sys/class/hwmon/hwmon0/temp1_input
# 25000  (= 25.0°C)

# Read all attributes
ls /sys/class/hwmon/hwmon0/
# name  temp1_input  temp1_max  temp1_max_hyst  ...
```

{: .note }
The `temp1_input` value is in millidegrees Celsius. Divide by 1000 for the human-readable temperature (25000 = 25.0°C).

### Step 4: Entity-Manager JSON Configuration

Entity-manager discovers hardware based on JSON configuration files. Create an entry for your platform that describes the sensor:

```json
{
    "Exposes": [
        {
            "Name": "Baseboard Temp",
            "Type": "TMP175",
            "Bus": 0,
            "Address": "0x48"
        }
    ],
    "Name": "My Platform Baseboard",
    "Probe": "TRUE"
}
```

Place this JSON in your meta-layer's entity-manager configurations directory:

```
meta-vendor/meta-platform/
  recipes-phosphor/configuration/
    entity-manager/
      my-platform-baseboard.json
```

See the [Entity Manager Guide]({% link docs/03-core-services/03-entity-manager-guide.md %}) for advanced probe expressions and configuration patterns.

### Step 5: dbus-sensors Pickup and D-Bus Exposure

The `dbus-sensors` package includes `hwmontempsensor`, which monitors entity-manager for matching configurations and exposes hwmon readings on D-Bus.

Once entity-manager publishes the configuration, `hwmontempsensor` automatically:
1. Matches the `Type` field to its supported sensor types
2. Opens the corresponding `/sys/class/hwmon/` sysfs path
3. Creates a D-Bus object at `/xyz/openbmc_project/sensors/temperature/Baseboard_Temp`
4. Polls the sysfs value and updates the D-Bus property

Verify on D-Bus:

```bash
# List temperature sensors
busctl tree xyz.openbmc_project.HwmonTempSensor

# Read the sensor value
busctl get-property xyz.openbmc_project.HwmonTempSensor \
    /xyz/openbmc_project/sensors/temperature/Baseboard_Temp \
    xyz.openbmc_project.Sensor.Value Value
# d 25.0
```

See the [D-Bus Sensors Guide]({% link docs/03-core-services/01-dbus-sensors-guide.md %}) and [hwmon Sensors Guide]({% link docs/03-core-services/02-hwmon-sensors-guide.md %}) for sensor types and thresholds.

### Step 6: Redfish Sensor Visibility

BMCWeb exposes D-Bus sensor objects as Redfish Sensor resources automatically:

```bash
# Query chassis sensors
curl -k -u root:0penBmc \
    https://localhost:2443/redfish/v1/Chassis/chassis/Sensors/temperature_Baseboard_Temp
```

Expected response (excerpt):

```json
{
    "@odata.id": "/redfish/v1/Chassis/chassis/Sensors/temperature_Baseboard_Temp",
    "Name": "Baseboard Temp",
    "Reading": 25.0,
    "ReadingUnits": "Cel",
    "ReadingType": "Temperature",
    "Status": {
        "State": "Enabled",
        "Health": "OK"
    }
}
```

### Cross-References

For deeper detail on each layer of the stack:
- [Entity Manager Guide]({% link docs/03-core-services/03-entity-manager-guide.md %}) — JSON probe expressions, multi-board configs
- [D-Bus Sensors Guide]({% link docs/03-core-services/01-dbus-sensors-guide.md %}) — sensor daemon architecture, threshold configuration
- [hwmon Sensors Guide]({% link docs/03-core-services/02-hwmon-sensors-guide.md %}) — hwmon sysfs attributes, supported chip types
- [I2C Device Integration Guide]({% link docs/03-core-services/16-i2c-device-integration-guide.md %}) — I2C bus configuration, device troubleshooting

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
| Build out-of-tree module | `bitbake my-hwmon-module` |
| Enable dynamic debug for module | `echo "module lm75 +p" > /sys/kernel/debug/dynamic_debug/control` |
| Start ftrace function_graph | `echo function_graph > /sys/kernel/debug/tracing/current_tracer` |
| Check GPIO state via debugfs | `cat /sys/kernel/debug/gpio` |
| Scan I2C bus | `i2cdetect -y 0` |
| Read I2C register | `i2cget -y 0 0x48 0x00 w` |
| Check deferred probes | `cat /sys/kernel/debug/devices_deferred` |

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
- [Yocto module.bbclass](https://docs.yoctoproject.org/ref-manual/classes.html#module) — out-of-tree kernel module recipe class
- [libgpiod Documentation](https://libgpiod.readthedocs.io/) — userspace GPIO access library (v2 API)
- [Linux UIO Documentation](https://www.kernel.org/doc/html/latest/driver-api/uio-howto.html) — Userspace I/O framework
- [Linux ftrace Documentation](https://www.kernel.org/doc/html/latest/trace/ftrace.html) — function tracer and function_graph tracer
- [Linux dynamic_debug](https://www.kernel.org/doc/html/latest/admin-guide/dynamic-debug-howto.html) — runtime debug print control
