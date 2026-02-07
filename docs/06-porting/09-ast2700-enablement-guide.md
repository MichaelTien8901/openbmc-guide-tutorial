---
layout: default
title: AST2700 Enablement
parent: Porting
nav_order: 9
difficulty: advanced
prerequisites:
  - porting-reference
  - machine-layer
last_modified_date: 2026-02-06
---

# AST2700 Enablement Guide
{: .no_toc }

Port OpenBMC to the ASPEED AST2700, the first 64-bit ARM BMC SoC with Caliptra silicon root of trust.
{: .fs-6 .fw-300 }

## Table of Contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

## Overview

The ASPEED AST2700 is ASPEED's next-generation BMC system-on-chip. It replaces the single-core 32-bit ARM Cortex-A7 of the AST2600 with a quad-core 64-bit ARM Cortex-A35 application processor alongside a dedicated real-time Cortex-M4F core. This architectural leap brings significantly more compute power, wider memory addressing, and new peripheral interfaces that align with emerging datacenter management standards.

Enabling the AST2700 in OpenBMC involves more than just adding a new machine configuration. The transition from 32-bit to 64-bit ARM changes the kernel architecture, compiler tuning, and pointer sizes across the entire userspace. New peripheral controllers for CAN bus, LTPI (LVDS Tunneling Protocol Interface), and USB 3.2 require kernel driver support and device tree bindings. Most notably, the AST2700 integrates Caliptra, an open-source silicon root of trust developed by the Open Compute Project, which enables measured boot and DICE-based identity certificates.

**Key concepts covered:**
- AST2600 vs AST2700 hardware comparison and migration path
- 64-bit ARM (aarch64) kernel and userspace configuration
- New peripheral interfaces: CAN, LTPI, USB 3.2, I3C
- Caliptra silicon root of trust and measured boot
- Upstream Linux kernel driver readiness for AST2700

{: .warning }
The AST2700 is a new SoC and upstream Linux kernel support is still evolving. Some drivers may be available only in ASPEED's vendor kernel tree at the time of writing. Always check the latest upstream kernel status before starting your port.

---

## AST2600 vs AST2700 Comparison

### Hardware Comparison Table

| Feature | AST2600 | AST2700 |
|---------|---------|---------|
| **CPU (Application)** | 1x ARM Cortex-A7 (32-bit) | 4x ARM Cortex-A35 (64-bit) |
| **CPU (Real-time)** | N/A | 1x ARM Cortex-M4F |
| **Architecture** | ARMv7-A (armhf) | ARMv8-A (aarch64) |
| **Max Clock** | 1.2 GHz | 1.6 GHz |
| **L2 Cache** | 256 KB | 512 KB (shared) |
| **DRAM** | DDR4, up to 2 GB (32-bit bus) | DDR5, up to 8 GB (64-bit bus) |
| **SPI NOR Flash** | 2x FMC + 2x SPI | 3x FMC + 2x SPI |
| **eMMC** | Yes (5.1) | Yes (5.1) |
| **Ethernet** | 4x RGMII/RMII | 4x RGMII/RMII + SGMII |
| **USB** | USB 2.0 Host/Hub | USB 3.2 Gen1 + USB 2.0 |
| **PCIe** | PCIe Gen2 x1 (RC) | PCIe Gen3 x2 (RC/EP) |
| **CAN Bus** | N/A | 2x CAN FD |
| **LTPI** | N/A | 2x LTPI |
| **I2C** | 16 buses | 16 buses |
| **I3C** | N/A | 6x I3C controllers |
| **GPIO** | ~228 pins | ~256 pins |
| **ADC** | 16-channel, 10-bit | 16-channel, 12-bit |
| **Video Engine** | 2D, JPEG/ASPEED codec | 2D, JPEG/ASPEED codec (improved) |
| **Security** | Secure Boot (OTP) | Caliptra Silicon RoT, Secure Boot |
| **Process Node** | 40nm | 12nm |

### Architecture Diagram

```
+------------------------------------------------------------------+
|                         AST2700 SoC                              |
+------------------------------------------------------------------+
|                                                                  |
|  +-------------------------------+   +-----------------------+   |
|  |   Application Processor       |   |   Real-Time Core      |   |
|  |   4x Cortex-A35 (AArch64)     |   |   Cortex-M4F          |   |
|  |   L2 Cache: 512 KB            |   |   SRAM: 256 KB        |   |
|  +-------------------------------+   +-----------------------+   |
|                    |                            |                |
|  +-----------------------------------------------------------+   |
|  |                System Interconnect (AXI/AHB)              |   |
|  +-----------------------------------------------------------+   |
|       |           |          |           |           |           |
|  +--------+  +--------+  +--------+  +--------+  +---------+     |
|  | DDR5   |  | SPI    |  | PCIe   |  | USB    |  | Caliptra|     |
|  | DRAM   |  | FMC    |  | Gen3   |  | 3.2    |  | RoT     |     |
|  +--------+  +--------+  +--------+  +--------+  +---------+     |
|       |           |          |           |                       |
|  +--------+  +--------+  +--------+  +--------+  +---------+     |
|  | Ether  |  | I2C    |  | I3C    |  | CAN FD |  | LTPI    |     |
|  | 4-port |  | 16-bus |  | 6-ctrl |  | 2-port |  | 2-port  |     |
|  +--------+  +--------+  +--------+  +--------+  +---------+     |
|                                                                  |
+------------------------------------------------------------------+
```

{: .note }
The Cortex-M4F real-time core runs independently from the Cortex-A35 cluster. It handles low-latency tasks such as fan control PID loops, GPIO event monitoring, and power sequencing. Communication between the two cores uses shared memory and inter-processor interrupts (IPI).

---

## 32-bit to 64-bit Migration

The transition from AST2600 (ARMv7-A, 32-bit) to AST2700 (ARMv8-A, 64-bit) affects every layer of the software stack: the kernel, bootloader, userspace libraries, and Yocto build configuration.

### Key Migration Changes

| Aspect | AST2600 (32-bit) | AST2700 (64-bit) |
|--------|-------------------|-------------------|
| **DEFAULTTUNE** | `arm1176jzs` or `cortexa7hf-neon` | `cortexa35` |
| **Kernel ARCH** | `arm` | `arm64` |
| **Kernel image** | `zImage` | `Image` |
| **Pointer size** | 4 bytes | 8 bytes |
| **`size_t` / `off_t`** | 32-bit | 64-bit |
| **Userspace ABI** | `arm-openbmc-linux-gnueabi` | `aarch64-openbmc-linux` |
| **Compiler flags** | `-marm -march=armv7-a` | `-march=armv8-a` |

### Machine Configuration for AST2700

```bitbake
# conf/machine/ast2700-bmc.conf

#@TYPE: Machine
#@NAME: AST2700 BMC
#@DESCRIPTION: OpenBMC for ASPEED AST2700-based platforms

# 64-bit ARM Cortex-A35 tuning
DEFAULTTUNE = "cortexa35"
require conf/machine/include/arm/armv8a/tune-cortexa35.inc

# Kernel configuration
PREFERRED_PROVIDER_virtual/kernel = "linux-aspeed"
KERNEL_IMAGETYPE = "Image"
KERNEL_DEVICETREE = "aspeed/aspeed-bmc-${MACHINE}.dtb"

# U-Boot configuration
PREFERRED_PROVIDER_virtual/bootloader = "u-boot-aspeed"
PREFERRED_PROVIDER_u-boot = "u-boot-aspeed"
UBOOT_MACHINE = "ast2700_openbmc_defconfig"
SPL_BINARY = "spl/u-boot-spl.bin"

# Flash layout (64MB SPI NOR)
FLASH_SIZE = "65536"
FLASH_UBOOT_OFFSET = "0"
FLASH_KERNEL_OFFSET = "2048"
FLASH_ROFS_OFFSET = "10240"
FLASH_RWFS_OFFSET = "55296"

# Console
SERIAL_CONSOLES = "115200;ttyS4"

# Machine features
MACHINE_FEATURES = "efi"
OBMC_MACHINE_FEATURES += "\
    obmc-bmc-state-mgmt \
    obmc-phosphor-fan-mgmt \
    obmc-phosphor-flash-mgmt \
"

# Entity Manager for dynamic inventory
VIRTUAL-RUNTIME_obmc-inventory-manager = "entity-manager"

# Include AST2700 base configuration
require conf/machine/include/ast2700.inc
require conf/machine/include/obmc-bsp-common.inc
```

{: .warning }
Do not mix 32-bit and 64-bit tunings. Setting `DEFAULTTUNE = "cortexa35"` ensures the entire sysroot is compiled for AArch64. If you accidentally inherit a 32-bit tune file, the build may succeed but produce a non-bootable image.

### Pointer Size and Code Portability

The move from 32-bit to 64-bit pointers affects C/C++ code that assumes pointer sizes:

```cpp
// BAD: Assumes pointer fits in 32-bit integer
uint32_t addr = (uint32_t)some_pointer;  // Truncates on 64-bit

// GOOD: Use uintptr_t for pointer-to-integer conversions
uintptr_t addr = (uintptr_t)some_pointer;  // Safe on both

// BAD: Assumes size_t is 32-bit
printf("size: %u\n", some_size_t_value);

// GOOD: Use %zu for size_t
printf("size: %zu\n", some_size_t_value);  // Portable
```

{: .tip }
Search your platform-specific recipes for `uint32_t` casts of pointers, hardcoded `4` as `sizeof(void*)`, and `%u` / `%lu` format strings for `size_t` values. These are the most common sources of 64-bit migration bugs.

### Kernel Configuration Changes

```bash
# meta-<machine>/recipes-kernel/linux/linux-aspeed/ast2700.cfg

# ===== Architecture =====
CONFIG_ARM64=y
CONFIG_ARCH_ASPEED=y
CONFIG_MACH_ASPEED_G7=y

# ===== SMP Support (quad-core) =====
CONFIG_SMP=y
CONFIG_NR_CPUS=4

# ===== AST2700 Peripheral Drivers =====
CONFIG_SERIAL_8250=y
CONFIG_SERIAL_8250_ASPEED=y
CONFIG_I2C_ASPEED=y
CONFIG_SPI_ASPEED_SMC=y
CONFIG_PINCTRL_ASPEED_G7=y
CONFIG_GPIO_ASPEED=y
CONFIG_SENSORS_ASPEED=y
CONFIG_WATCHDOG_ASPEED=y
CONFIG_USB_XHCI_HCD=y
CONFIG_CAN=y
CONFIG_CAN_ASPEED=y

# ===== Real-Time Core Communication =====
CONFIG_MAILBOX=y
CONFIG_ASPEED_MBOX=y

# ===== Security =====
CONFIG_CRYPTO=y
CONFIG_CRYPTO_SHA256=y
CONFIG_CRYPTO_SHA384=y
CONFIG_CRYPTO_SHA512=y
```

Apply this fragment in your kernel bbappend:

```bitbake
# meta-<machine>/recipes-kernel/linux/linux-aspeed_%.bbappend

FILESEXTRAPATHS:prepend := "${THISDIR}/linux-aspeed:"
SRC_URI += "file://ast2700.cfg"
```

---

## New Peripheral Interfaces

The AST2700 introduces several new peripheral controllers not present on the AST2600.

### CAN FD (Controller Area Network Flexible Data-Rate)

The AST2700 includes two CAN FD controllers for communication with platform management controllers, power supplies, and chassis management devices. CAN FD supports data rates up to 8 Mbps with 64-byte payloads.

#### Device Tree and Usage

```dts
&can0 {
    status = "okay";
    pinctrl-names = "default";
    pinctrl-0 = <&pinctrl_can0_default>;
    can-transceiver {
        max-bitrate = <8000000>;
    };
};
```

```bash
# Bring up CAN interface
ip link set can0 type can bitrate 500000 dbitrate 4000000 fd on
ip link set can0 up

# Send and monitor CAN FD frames
cansend can0 123##1.DEADBEEF
candump can0
```

### LTPI (LVDS Tunneling Protocol Interface)

LTPI is an OCP-specified interface for tunneling low-speed management buses (I2C, GPIO, UART) over a single LVDS differential pair. It reduces cable count between the BMC and host or satellite boards, as defined in the DC-SCM 2.0 specification.

```dts
&ltpi0 {
    status = "okay";
    pinctrl-names = "default";
    pinctrl-0 = <&pinctrl_ltpi0_default>;
    aspeed,mode = "bmc";       /* "bmc" or "host" */
    i2c-channels = <4>;        /* Tunneled I2C buses */
    gpio-channels = <16>;      /* Tunneled GPIO pins */
    uart-channels = <1>;       /* Tunneled UARTs */
};
```

| Use Case | Description |
|----------|-------------|
| **DC-SCM 2.0** | Single-cable BMC-to-host board connection |
| **Satellite BMC** | Remote I2C/GPIO access to expansion chassis |
| **Cable reduction** | Replace multiple ribbon cables with one LVDS pair |

{: .note }
LTPI driver support is currently available only in ASPEED's vendor kernel tree. Track upstream submission at the [linux-aspeed mailing list](https://lists.ozlabs.org/listinfo/linux-aspeed).

### USB 3.2 Gen1

The AST2700 upgrades from USB 2.0 to USB 3.2 Gen1 (5 Gbps), enabling faster virtual media, firmware updates, and diagnostic data transfer.

```dts
&usb {
    status = "okay";
    xhci@1e6a0000 {
        compatible = "aspeed,ast2700-xhci";
        reg = <0x1e6a0000 0x1000>;
        interrupts = <GIC_SPI 14 IRQ_TYPE_LEVEL_HIGH>;
        phys = <&usb3_phy>;
        phy-names = "usb3-phy";
    };
};
```

```bash
# Kernel configuration for USB 3.2
CONFIG_USB_XHCI_HCD=y
CONFIG_USB_XHCI_PLATFORM=y
CONFIG_USB_ASPEED_XHCI=y
CONFIG_USB_GADGET=y
CONFIG_USB_CONFIGFS_MASS_STORAGE=y
```

### I3C (Improved Inter-Integrated Circuit)

The AST2700 includes six I3C controllers for next-generation sensors and memory devices using the MIPI I3C protocol.

```dts
&i3c0 {
    status = "okay";
    i3c-scl-hz = <12500000>;    /* 12.5 MHz I3C mode */
    i2c-scl-hz = <400000>;      /* 400 KHz I2C fallback */

    temperature-sensor@48,39200000000 {
        reg = <0x48 0x392 0x00000000>;
        assigned-address = <0x48>;
    };
};
```

{: .tip }
I3C is backward-compatible with I2C. You can connect legacy I2C sensors to an I3C bus in mixed mode. The controller automatically handles the protocol difference for each device.

---

## Caliptra Silicon Root of Trust

The AST2700 integrates Caliptra, an open-source silicon root of trust (RoT) developed by the Open Compute Project (OCP). Caliptra provides hardware-rooted security features that are immutable after manufacturing.

### Caliptra Components

| Component | Function |
|-----------|----------|
| **DICE Engine** | Generates identity certificates bound to firmware measurements |
| **SHA-384/512** | Hashes firmware images for measured boot |
| **ECC-384** | Signs and verifies certificates and attestation data |
| **HMAC Engine** | Derives keys from compound device identifiers |
| **Key Vault** | Stores sealed keys accessible only to authorized firmware |
| **Mailbox** | Hardware interface for BMC firmware communication |

### Measured Boot Flow

Caliptra implements a measured boot chain where each firmware stage is hashed before execution. Measurements are stored in Platform Configuration Registers (PCRs) inside the Caliptra hardware.

| Boot Stage | Measured By | PCR | Description |
|------------|-------------|-----|-------------|
| Caliptra FMC | Caliptra ROM | PCR[0] | First Mutable Code, DICE CDI derived |
| Caliptra Runtime | Caliptra FMC | PCR[1] | Runtime firmware, certificate chain extended |
| U-Boot SPL | Caliptra RT | PCR[2] | First BMC boot stage |
| U-Boot | U-Boot SPL | PCR[3] | Hash sent to Caliptra via mailbox |
| FIT Image | U-Boot | PCR[4] | Kernel + device tree blob |

After the kernel boots, Caliptra Runtime remains active and serves attestation requests via SPDM over MCTP.

### DICE Certificate Chain

Caliptra generates a DICE (Device Identifier Composition Engine) certificate chain that cryptographically binds device identity to the specific firmware running on it.

| Certificate | Issuer | Contains |
|-------------|--------|----------|
| **DeviceID Cert** | Manufacturer CA | Unique device identity (from OTP fuses) |
| **Alias Cert (FMC)** | DeviceID | Measurement of FMC firmware |
| **Alias Cert (RT)** | FMC Alias | Measurement of Runtime firmware |
| **Alias Cert (BMC)** | RT Alias | Measurement of U-Boot + Kernel |

{: .note }
The DICE certificate chain changes any time firmware is updated, because the measurements change. Remote attestation services use this chain to verify platform integrity before granting access to secrets or workloads.

### Caliptra Mailbox Interface

The BMC firmware communicates with Caliptra through a hardware mailbox for sending measurements, requesting certificates, and performing cryptographic operations.

```c
/* Caliptra mailbox register map (simplified) */
#define CALIPTRA_MBOX_CMD       0x1e6f0000  /* Command register */
#define CALIPTRA_MBOX_DLEN      0x1e6f0004  /* Data length */
#define CALIPTRA_MBOX_DATAIN    0x1e6f0008  /* Data input FIFO */
#define CALIPTRA_MBOX_DATAOUT   0x1e6f000c  /* Data output FIFO */
#define CALIPTRA_MBOX_STATUS    0x1e6f0010  /* Status register */

/* Common mailbox commands */
#define CALIPTRA_CMD_STASH_MEASUREMENT  0x434D5348  /* "CMSH" */
#define CALIPTRA_CMD_GET_IDEV_CERT      0x49444556  /* "IDEV" */
#define CALIPTRA_CMD_GET_FMC_ALIAS_CERT 0x464D4341  /* "FMCA" */
```

### Enabling Caliptra in OpenBMC

```bash
# Kernel configuration for Caliptra
CONFIG_ASPEED_CALIPTRA=y
CONFIG_ASPEED_CALIPTRA_MBOX=y
CONFIG_TCG_TPM=y
CONFIG_TCG_CALIPTRA=y
```

```bitbake
# recipes-bsp/u-boot/u-boot-aspeed_%.bbappend
# Enable Caliptra measured boot in U-Boot
EXTRA_OEMAKE:append = " CALIPTRA=1"
```

Caliptra's runtime firmware supports SPDM for remote attestation, allowing a verifier to request measurement logs and DICE certificates over MCTP:

```bash
# Check Caliptra attestation readiness
busctl tree xyz.openbmc_project.SPDM

# Query Caliptra device identity
busctl get-property xyz.openbmc_project.SPDM \
    /xyz/openbmc_project/spdm/caliptra \
    xyz.openbmc_project.SPDM.Responder CertificateChain
```

{: .tip }
If your platform does not require measured boot, you can leave Caliptra in its default pass-through mode. The boot flow proceeds normally without measurement enforcement, but you lose remote attestation capability.

---

## Upstream Linux Kernel Driver Readiness

### Driver Readiness Table

| Peripheral | Driver | Upstream Status | Kernel Version | Notes |
|------------|--------|-----------------|----------------|-------|
| **UART (16550)** | `8250_aspeed` | Merged | v6.6+ | Standard 16550-compatible |
| **I2C** | `i2c-aspeed` | Merged | v6.8+ | AST2700 register updates |
| **SPI FMC** | `spi-aspeed-smc` | Merged | v6.8+ | New FMC3 controller |
| **GPIO** | `gpio-aspeed` | Merged | v6.9+ | Extended pin count (256) |
| **Pinctrl** | `pinctrl-aspeed-g7` | Merged | v6.9+ | New G7 pin mux tables |
| **Watchdog** | `aspeed_wdt` | Merged | v6.8+ | Dual watchdog support |
| **ADC** | `aspeed_adc` | Merged | v6.10+ | 12-bit resolution |
| **PECI** | `peci-aspeed` | Merged | v6.8+ | Enhanced PECI 4.0 |
| **Ethernet** | `ftgmac100` | Merged | v6.9+ | SGMII PHY support |
| **eMMC/SD** | `sdhci-aspeed` | Merged | v6.8+ | eMMC 5.1 support |
| **PWM/Fan** | `aspeed-pwm-tacho` | Merged | v6.10+ | Updated for G7 |
| **USB 3.2 xHCI** | `xhci-aspeed` | In review | -- | Expected v6.12+ |
| **CAN FD** | `can-aspeed` | In review | -- | Expected v6.12+ |
| **I3C** | `i3c-aspeed` | In review | -- | Expected v6.13+ |
| **LTPI** | `ltpi-aspeed` | Not submitted | -- | Vendor tree only |
| **Caliptra Mbox** | `caliptra-aspeed` | In review | -- | OCP working group |
| **Video Engine** | `aspeed-video` | Partial | v6.9+ | G7 updates pending |
| **MCTP/PCIe EP** | `mctp-pcie-aspeed` | Partial | v6.10+ | Gen3 EP pending |
| **GIC-600** | `irq-gic-v3` | Merged | v6.6+ | Standard ARM GICv3 |
| **Timer** | `arm_arch_timer` | Merged | v6.6+ | Standard ARM timer |

{: .warning }
Drivers marked "In review" or "Not submitted" require ASPEED's vendor kernel tree or backported patches. Track status at the [linux-aspeed mailing list](https://lists.ozlabs.org/listinfo/linux-aspeed) and [LKML](https://lore.kernel.org/linux-arm-kernel/?q=aspeed+ast2700).

### Kernel Source Strategy

| Strategy | When to Use | Pros | Cons |
|----------|-------------|------|------|
| **Upstream mainline** | All required drivers merged | Community support, long-term maintenance | May lack newest features |
| **ASPEED vendor kernel** | Need CAN, LTPI, Caliptra, USB 3.2 | Full feature set | Vendor maintenance burden |
| **Upstream + backports** | Most drivers merged, need a few extras | Best of both worlds | Patch maintenance |

```bitbake
# Using ASPEED vendor kernel (recommended for early AST2700 enablement)
# recipes-kernel/linux/linux-aspeed_%.bbappend

FILESEXTRAPATHS:prepend := "${THISDIR}/linux-aspeed:"

SRC_URI = "git://github.com/AspeedTech-BMC/linux;branch=aspeed-master-v6.6"
SRCREV = "${AUTOREV}"

SRC_URI += "\
    file://ast2700.cfg \
    file://ast2700-can.cfg \
    file://ast2700-caliptra.cfg \
"
```

{: .tip }
Start with the ASPEED vendor kernel for initial bring-up, then migrate to upstream mainline as drivers are merged. Track which patches you carry and their upstream submission status.

---

## Troubleshooting

### Issue: Kernel Fails to Boot on AST2700

**Symptom**: U-Boot loads the FIT image but the kernel hangs after "Starting kernel..."

**Cause**: Kernel compiled for 32-bit ARM (`zImage`) instead of 64-bit ARM (`Image`), or missing GICv3 device tree configuration.

**Solution**:
1. Verify `KERNEL_IMAGETYPE = "Image"` in machine configuration (not `zImage`)
2. Confirm `DEFAULTTUNE = "cortexa35"` is set
3. Check that the device tree includes the GICv3 interrupt controller node
4. Verify U-Boot uses `booti` command (not `bootz`)

### Issue: Userspace Segfaults After 64-bit Migration

**Symptom**: OpenBMC daemons crash with segmentation faults that did not occur on AST2600.

**Cause**: Code that casts pointers to 32-bit integers or assumes 32-bit pointer width.

**Solution**:
1. Rebuild with `-Wall -Wpointer-to-int-cast` to catch truncation warnings
2. Search for `(uint32_t)` casts applied to pointer values
3. Replace `%u` format specifiers for `size_t` with `%zu`
4. Use `sizeof()` instead of hardcoded `4` for pointer sizes

### Issue: CAN or LTPI Drivers Not Found

**Symptom**: `ip link show` does not list CAN interfaces, or LTPI tunneled buses are not visible.

**Cause**: Upstream kernel does not yet include these drivers.

**Solution**:
1. Switch to the ASPEED vendor kernel branch
2. Verify the driver is enabled in your kernel config fragment
3. Check `dmesg | grep -i can` or `dmesg | grep -i ltpi` for probe messages
4. Confirm device tree nodes have `status = "okay"` and correct pin control

### Issue: Caliptra Mailbox Timeout

**Symptom**: U-Boot or kernel reports "Caliptra mailbox timeout" during boot.

**Cause**: Caliptra firmware not loaded, mailbox misconfigured, or Caliptra core held in reset.

**Solution**:
1. Verify Caliptra firmware is loaded into the correct flash region
2. Check that Caliptra reset is deasserted in the SCU (System Control Unit)
3. Inspect mailbox status register at `0x1e6f0010` for error flags
4. Ensure `caliptra_reserved` memory region does not overlap other allocations

### Debug Commands

```bash
# Check CPU architecture and core count
lscpu
# Should show: Architecture: aarch64, CPU(s): 4

# Verify device tree model
cat /proc/device-tree/model

# Check for AST2700-specific peripherals
dmesg | grep -i ast2700
dmesg | grep -i caliptra
dmesg | grep -i "can\|ltpi\|xhci\|i3c"

# List all I2C/I3C buses (including LTPI-tunneled)
i2cdetect -l

# Verify 64-bit userspace
file /usr/bin/bmcweb
# Should show: ELF 64-bit LSB executable, ARM aarch64
```

---

## References

### Official Resources
- [ASPEED AST2700 Product Page](https://www.aspeedtech.com/server_management/ast2700/)
- [OpenBMC meta-aspeed Layer](https://github.com/openbmc/openbmc/tree/master/meta-aspeed)
- [ASPEED Linux Kernel Tree](https://github.com/AspeedTech-BMC/linux)
- [ASPEED U-Boot Tree](https://github.com/AspeedTech-BMC/u-boot)

### Caliptra Resources
- [Caliptra Specification (OCP)](https://github.com/chipsalliance/caliptra)
- [Caliptra RTL (CHIPS Alliance)](https://github.com/chipsalliance/caliptra-rtl)
- [Caliptra Software (CHIPS Alliance)](https://github.com/chipsalliance/caliptra-sw)
- [DICE Architecture (TCG)](https://trustedcomputinggroup.org/resource/dice-attestation-architecture/)

### Related Guides
- [Porting Reference]({% link docs/06-porting/01-porting-reference.md %})
- [Machine Layer Guide]({% link docs/06-porting/02-machine-layer.md %})
- [Device Tree Guide]({% link docs/06-porting/03-device-tree.md %})
- [U-Boot Guide]({% link docs/06-porting/04-uboot.md %})
- [ARM Platform Guide]({% link docs/06-porting/06-arm-platform-guide.md %})
- [Flash Layout & Optimization Guide]({% link docs/06-porting/08-flash-layout-optimization-guide.md %})

### External Documentation
- [ARM Cortex-A35 Technical Reference](https://developer.arm.com/documentation/100236/latest/)
- [Linux ARM64 Documentation](https://docs.kernel.org/arch/arm64/)
- [OCP DC-SCM 2.0 Specification](https://www.opencompute.org/documents/ocp-dc-scm-spec-rev-2-0-pdf)
- [MIPI I3C Specification](https://www.mipi.org/specifications/i3c-sensor-specification)

---

{: .note }
**Tested on**: Reference documentation based on ASPEED AST2700 EVB and vendor SDK materials. Upstream kernel driver status reflects early 2026. Always verify current driver availability before starting your port.
Last updated: 2026-02-06
