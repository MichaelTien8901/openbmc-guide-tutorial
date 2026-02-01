---
layout: default
title: eSPI Guide
parent: Advanced Topics
nav_order: 9
difficulty: advanced
prerequisites:
  - openbmc-overview
  - porting-reference
---

# eSPI Guide
{: .no_toc }

Configure and use eSPI (Enhanced Serial Peripheral Interface) for BMC-to-host communication on OpenBMC.
{: .fs-6 .fw-300 }

## Table of Contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

## Overview

eSPI (Enhanced Serial Peripheral Interface) is Intel's successor to LPC (Low Pin Count), providing higher bandwidth and lower pin count for BMC-to-host communication. Modern Intel and AMD platforms use eSPI exclusively for BMC connectivity.

### eSPI vs LPC Comparison

| Feature | LPC | eSPI |
|---------|-----|------|
| **Pins** | 13 signals | 4-6 signals |
| **Bandwidth** | 16.67 MB/s (33 MHz) | 66 MB/s (66 MHz quad I/O) |
| **Voltage** | 3.3V only | 1.8V or 3.3V |
| **Channels** | Single | 4 independent channels |
| **Alert** | SERIRQ | Alert# pin + in-band |
| **Flash Access** | Separate SPI | Integrated flash channel |

### eSPI Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        eSPI Architecture                                     │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   ┌─────────────────────────────────────────────────────────────────────┐   │
│   │                         Host (Intel/AMD PCH)                         │   │
│   │                                                                      │   │
│   │   ┌──────────────────────────────────────────────────────────────┐  │   │
│   │   │                    eSPI Controller (Master)                   │  │   │
│   │   └──────────────────────────────────────────────────────────────┘  │   │
│   └──────────────────────────────┬───────────────────────────────────────┘   │
│                                  │                                           │
│            ┌─────────────────────┼─────────────────────┐                    │
│            │                     │                     │                    │
│         CS#│                  CLK│               IO[3:0]                    │
│            │                     │              (Quad SPI)                   │
│            │                     │                     │                    │
│            │    Alert#           │      Reset#         │                    │
│            │       │             │         │           │                    │
│   ┌────────┴───────┴─────────────┴─────────┴───────────┴────────────────┐   │
│   │                         eSPI Bus                                     │   │
│   └────────┬───────┬─────────────┬─────────┬───────────┬────────────────┘   │
│            │       │             │         │           │                    │
│   ┌────────┴───────┴─────────────┴─────────┴───────────┴────────────────┐   │
│   │                                                                      │   │
│   │   ┌──────────────────────────────────────────────────────────────┐  │   │
│   │   │                    eSPI Controller (Slave)                    │  │   │
│   │   │                                                               │  │   │
│   │   │  ┌────────────┐ ┌────────────┐ ┌────────────┐ ┌────────────┐ │  │   │
│   │   │  │ Peripheral │ │  Virtual   │ │    OOB     │ │   Flash    │ │  │   │
│   │   │  │  Channel   │ │   Wire     │ │  Message   │ │   Access   │ │  │   │
│   │   │  │ (I/O,MMIO) │ │  Channel   │ │  Channel   │ │  Channel   │ │  │   │
│   │   │  └────────────┘ └────────────┘ └────────────┘ └────────────┘ │  │   │
│   │   └──────────────────────────────────────────────────────────────┘  │   │
│   │                                                                      │   │
│   │                    BMC (ASPEED AST2500/2600)                         │   │
│   └──────────────────────────────────────────────────────────────────────┘   │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### eSPI Channel Types

eSPI provides four independent channels, each serving different communication needs:

| Channel | Purpose | Use Cases |
|---------|---------|-----------|
| **Peripheral** | Memory-mapped I/O and I/O cycles | LPC-compatible peripherals, IPMI KCS, POST codes |
| **Virtual Wire** | GPIO-like signals | Power states (SLP_S3/S4/S5), PLTRST#, interrupts |
| **OOB Message** | SMBus-like messaging | Platform alerts, tunneled SMBus, MCTP |
| **Flash Access** | SPI flash sharing | Host BIOS on BMC-attached flash (eDAF) |

### Channel Selection Guide

```
What do you need to communicate?
       │
       ├── Register/memory access (I/O ports, MMIO)?
       │        └── Peripheral Channel
       │
       ├── Simple signals (power state, reset, interrupts)?
       │        └── Virtual Wire Channel
       │
       ├── Messages/packets (alerts, SMBus, MCTP)?
       │        └── OOB Message Channel
       │
       └── Flash access (host BIOS, shared flash)?
                └── Flash Access Channel
```

---

## Virtual Wire Channel

Virtual wires provide GPIO-like signaling between host and BMC, replacing dedicated LPC signals with software-defined wires.

### Virtual Wire Signal Table

| Index | Signal | Direction | Active | Purpose |
|-------|--------|-----------|--------|---------|
| 2 | SLP_S3# | Host→BMC | Low | S3 sleep state indicator |
| 3 | SLP_S4# | Host→BMC | Low | S4 sleep state indicator |
| 4 | SLP_S5# | Host→BMC | Low | S5 sleep state indicator |
| 5 | SLP_A# | Host→BMC | Low | SLP_A signal |
| 6 | SLP_LAN# | Host→BMC | Low | LAN sleep signal |
| 7 | SLP_WLAN# | Host→BMC | Low | WLAN sleep signal |
| 41 | PLTRST# | Host→BMC | Low | Platform reset |
| 42 | SUS_STAT# | Host→BMC | Low | Suspend status |
| 43 | SUS_PWRDN_ACK | BMC→Host | High | Suspend power down ack |
| 44 | SUS_WARN# | Host→BMC | Low | Suspend warning |
| 45 | OOB_RST_WARN | Host→BMC | High | OOB reset warning |
| 46 | OOB_RST_ACK | BMC→Host | High | OOB reset acknowledge |
| 47 | HOST_RST_WARN | Host→BMC | High | Host reset warning |
| 48 | HOST_RST_ACK | BMC→Host | High | Host reset acknowledge |
| 64-127 | GPIO | Bi-dir | Config | Platform-specific GPIOs |

### Common Virtual Wires Explained

**Power State Signals (SLP_S3#, SLP_S4#, SLP_S5#):**

These signals indicate ACPI sleep states:
- **SLP_S3#**: Low when system enters S3 (suspend to RAM)
- **SLP_S4#**: Low when system enters S4 (hibernate)
- **SLP_S5#**: Low when system enters S5 (soft off)

```
Power State Detection:
┌──────────────────────────────────────────────────┐
│ SLP_S3# │ SLP_S4# │ SLP_S5# │ System State       │
├─────────┼─────────┼─────────┼────────────────────┤
│  High   │  High   │  High   │ S0 (Running)       │
│  Low    │  High   │  High   │ S3 (Suspend RAM)   │
│  High   │  Low    │  High   │ S4 (Hibernate)     │
│  High   │  High   │  Low    │ S5 (Soft Off)      │
│  Low    │  Low    │  Low    │ Mechanical Off     │
└─────────┴─────────┴─────────┴────────────────────┘
```

**Platform Reset (PLTRST#):**

PLTRST# indicates platform reset state:
- Low during host reset sequence
- High when host completes reset
- BMC uses this to detect host boot status

### Virtual Wire to GPIO Mapping

OpenBMC maps virtual wires to GPIO interfaces for integration with existing services:

```bash
# Virtual wires appear as GPIO lines
gpioinfo | grep -i espi
# gpiochip1 - 8 lines:
#     line 0: "espi-vw-slp-s3" input
#     line 1: "espi-vw-slp-s4" input
#     line 2: "espi-vw-slp-s5" input
#     line 3: "espi-vw-pltrst" input

# Read virtual wire state
gpioget gpiochip1 0  # Read SLP_S3#

# Monitor virtual wire changes
gpiomon gpiochip1 0 1 2 3
```

### Device Tree Configuration for Virtual Wires

```dts
// ASPEED AST2600 eSPI Virtual Wire configuration

&espi {
    status = "okay";

    espi_vw: espi-vw {
        compatible = "aspeed,ast2600-espi-vw";
        status = "okay";

        /* Map system virtual wires to GPIO lines */
        gpio-controller;
        #gpio-cells = <2>;
        gpio-line-names =
            "espi-vw-slp-s3",    /* VW index 2 */
            "espi-vw-slp-s4",    /* VW index 3 */
            "espi-vw-slp-s5",    /* VW index 4 */
            "espi-vw-pltrst",    /* VW index 41 */
            "espi-vw-sus-stat",  /* VW index 42 */
            "espi-vw-sus-warn",  /* VW index 44 */
            "espi-vw-oob-rst-warn", /* VW index 45 */
            "espi-vw-host-rst-warn"; /* VW index 47 */
    };
};
```

### ASPEED eSPI Virtual Wire Driver

**Kernel Configuration:**

```kconfig
CONFIG_ASPEED_ESPI=y
CONFIG_ASPEED_ESPI_VW=y
```

**Driver Module Parameters:**

```bash
# View current parameters
cat /sys/module/aspeed_espi_vw/parameters/*

# Virtual wire index mapping configured via device tree
```

**Sysfs Interface:**

```bash
# Virtual wire status
cat /sys/bus/platform/devices/*.espi-vw/status

# Debug information
cat /sys/kernel/debug/aspeed-espi-vw/vw_status
```

### Virtual Wire Troubleshooting

**Issue: Virtual wire signals not changing**

```bash
# 1. Verify eSPI controller is enabled
cat /sys/bus/platform/devices/*.espi/enabled
# Should show "1"

# 2. Check eSPI negotiation completed
dmesg | grep -i espi
# Look for "eSPI channel X enabled"

# 3. Verify virtual wire channel enabled
cat /sys/bus/platform/devices/*.espi/vw_channel_enabled

# 4. Read raw virtual wire registers
devmem 0x1e6ee080  # ASPEED VW status register (example)

# 5. Check for interrupt activity
cat /proc/interrupts | grep espi
```

**Issue: Wrong polarity or stuck signals**

```bash
# Check device tree gpio-active-low settings
# Verify host chipset VW configuration
# Check for electrical issues on eSPI bus
```

---

## eSPI Console/UART

eSPI can provide UART functionality through the peripheral channel, replacing dedicated UART pins.

### eSPI UART Operation

```
┌─────────────────────────────────────────────────────────────┐
│                    eSPI UART Flow                            │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│   Host                                                       │
│   ┌─────────────────────────────────────────────────────┐   │
│   │  Legacy COM Port (I/O 0x3F8)                        │   │
│   │         │                                            │   │
│   │         ▼                                            │   │
│   │  eSPI Peripheral Channel (I/O Cycles)               │   │
│   └─────────────────────────────────────────────────────┘   │
│                           │                                  │
│                    eSPI Bus                                  │
│                           │                                  │
│   BMC                     ▼                                  │
│   ┌─────────────────────────────────────────────────────┐   │
│   │  eSPI Peripheral Channel Decoder                    │   │
│   │         │                                            │   │
│   │         ▼                                            │   │
│   │  Virtual UART (ttyS* or ttyVUART*)                  │   │
│   └─────────────────────────────────────────────────────┘   │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### Kernel Configuration for eSPI UART

```kconfig
# ASPEED eSPI UART support
CONFIG_ASPEED_ESPI=y
CONFIG_ASPEED_ESPI_PERIPHERAL=y
CONFIG_SERIAL_8250=y
CONFIG_SERIAL_8250_ASPEED_VUART=y
```

### Device Tree for eSPI UART

```dts
// ASPEED eSPI with UART over peripheral channel

&espi {
    status = "okay";

    espi_peri: espi-peripheral {
        compatible = "aspeed,ast2600-espi-peripheral";
        status = "okay";

        /* UART over eSPI peripheral channel */
        uart-over-espi;
        uart-io-base = <0x3f8>;  /* COM1 I/O address */
    };
};

/* Virtual UART configuration */
&vuart1 {
    status = "okay";
    aspeed,sirq = <4>;  /* IRQ 4 for COM1 */
    aspeed,lpc-io-reg = <0x3f8>;
};
```

### Using eSPI UART

```bash
# List serial devices
ls -la /dev/ttyS* /dev/ttyVUART*

# Configure serial parameters
stty -F /dev/ttyVUART0 115200 cs8 -cstopb -parenb

# Connect to host console
screen /dev/ttyVUART0 115200

# Or use obmc-console
systemctl status obmc-console@ttyVUART0
```

### SOL over eSPI OOB Channel

Serial over LAN can also use eSPI OOB channel for IPMI SOL:

```bash
# Configure IPMI SOL to use eSPI-backed UART
# In phosphor-ipmi-host configuration

# SOL activation uses standard IPMI commands
ipmitool -I lanplus -H <bmc-ip> -U root -P password sol activate
```

---

## OOB Message Channel

The OOB (Out-of-Band) Message Channel provides SMBus-like packet communication between host and BMC.

### OOB Channel Overview

```
┌─────────────────────────────────────────────────────────────┐
│                    OOB Message Format                        │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌─────────┬─────────┬─────────┬─────────────┬───────────┐  │
│  │  Cycle  │   Tag   │  Length │   Address   │  Data     │  │
│  │  Type   │         │         │  (optional) │           │  │
│  │ (1 byte)│(1 byte) │(2 bytes)│  (varies)   │ (varies)  │  │
│  └─────────┴─────────┴─────────┴─────────────┴───────────┘  │
│                                                              │
│  Cycle Types:                                                │
│  - 0x21: OOB SMBus Write                                    │
│  - 0x22: OOB SMBus Read                                     │
│  - 0x23-0x27: Reserved/Vendor-specific                      │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### OOB Use Cases

| Use Case | Description |
|----------|-------------|
| **Platform Alerts** | BMC sends alerts to host (thermal, power, errors) |
| **Tunneled SMBus** | SMBus transactions over eSPI (sensor access) |
| **MCTP over eSPI** | PLDM/MCTP messages over OOB channel |
| **Vendor Commands** | Platform-specific communication |

### Kernel Configuration for OOB

```kconfig
CONFIG_ASPEED_ESPI=y
CONFIG_ASPEED_ESPI_OOB=y
```

### Device Tree for OOB Channel

```dts
&espi {
    status = "okay";

    espi_oob: espi-oob {
        compatible = "aspeed,ast2600-espi-oob";
        status = "okay";

        /* OOB channel configuration */
        oob-channel-enable;
    };
};
```

### Sending/Receiving OOB Messages

```bash
# OOB interface (platform-specific)
# Typically accessed via character device or netlink

# Check OOB channel status
cat /sys/bus/platform/devices/*.espi-oob/status

# Debug OOB messages
echo 1 > /sys/kernel/debug/aspeed-espi-oob/trace_enable
cat /sys/kernel/debug/aspeed-espi-oob/trace
```

---

## Flash Access Channel & eDAF

The Flash Access Channel enables the host to access SPI flash attached to the BMC, enabling eDAF (eSPI Direct Attached Flash) boot.

### eDAF Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        eDAF Architecture                                    │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│   ┌─────────────────────────────────────────────────────────────────────┐   │
│   │                         Host CPU                                    │   │
│   │                                                                     │   │
│   │  1. CPU requests BIOS from flash                                    │   │
│   │         │                                                           │   │
│   │         ▼                                                           │   │
│   │  2. PCH sends flash read via eSPI Flash Channel                     │   │
│   └─────────────────────────────────────────────────────────────────────┘   │
│                                  │                                          │
│                           eSPI Bus                                          │
│                                  │                                          │
│   ┌─────────────────────────────────────────────────────────────────────┐   │
│   │                         BMC                                         │   │
│   │                                                                     │   │
│   │  3. eSPI controller receives flash request                          │   │
│   │         │                                                           │   │
│   │         ▼                                                           │   │
│   │  4. Flash Access Channel controller                                 │   │
│   │         │                                                           │   │
│   │         ▼                                                           │   │
│   │  5. SPI flash controller reads from flash                           │   │
│   │         │                                                           │   │
│   │         ▼                                                           │   │
│   │  ┌─────────────────────────────────────────────────────────────┐    │   │
│   │  │              SPI Flash (Shared)                             │    │   │
│   │  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐  │    │   │
│   │  │  │ BMC Region  │  │ Host BIOS   │  │ Shared/Other        │  │    │   │
│   │  │  │ (U-Boot,    │  │ Region      │  │ Regions             │  │    │   │
│   │  │  │  Kernel,    │  │ (UEFI)      │  │                     │  │    │   │
│   │  │  │  RootFS)    │  │             │  │                     │  │    │   │
│   │  │  └─────────────┘  └─────────────┘  └─────────────────────┘  │    │   │
│   │  └─────────────────────────────────────────────────────────────┘    │   │
│   │                                                                     │   │
│   │  6. Data returned via eSPI to host                                  │   │
│   └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### eDAF Boot Flow

```
┌─────────────────────────────────────────────────────────────┐
│                    eDAF Boot Sequence                       │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  1. System power on                                         │
│         │                                                   │
│         ▼                                                   │
│  2. BMC boots first (from BMC flash region)                 │
│         │                                                   │
│         ▼                                                   │
│  3. BMC initializes eSPI controller                         │
│     - Configures flash access channel                       │
│     - Sets up address mapping                               │
│         │                                                   │
│         ▼                                                   │
│  4. BMC releases host reset (PLTRST#)                       │
│         │                                                   │
│         ▼                                                   │
│  5. Host CPU starts, fetches BIOS via eSPI                  │
│         │                                                   │
│         ▼                                                   │
│  6. eSPI flash reads routed to BMC-attached flash           │
│         │                                                   │
│         ▼                                                   │
│  7. Host BIOS executes, system boots normally               │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### Flash Layout for eDAF

```
┌─────────────────────────────────────────────────────────────┐
│              Shared SPI Flash Layout (64MB example)         │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  Offset      │ Size   │ Region         │ Access             │
│ ─────────────┼────────┼────────────────┼──────────────────  │
│  0x00000000  │ 512KB  │ U-Boot         │ BMC only           │
│  0x00080000  │ 64KB   │ U-Boot Env     │ BMC only           │
│  0x00090000  │ ~7MB   │ BMC Kernel     │ BMC only           │
│  0x00800000  │ 24MB   │ BMC RootFS     │ BMC only           │
│  0x02000000  │ 16MB   │ Host BIOS      │ Host via eSPI      │
│  0x03000000  │ 16MB   │ Host BIOS (B)  │ Host via eSPI      │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### MTD Partition Configuration

```dts
// Device tree flash partition for eDAF

&fmc {
    status = "okay";
    flash@0 {
        status = "okay";
        m25p,fast-read;
        label = "bmc";
        spi-max-frequency = <50000000>;

        partitions {
            compatible = "fixed-partitions";
            #address-cells = <1>;
            #size-cells = <1>;

            u-boot@0 {
                reg = <0x0 0x80000>;
                label = "u-boot";
            };

            u-boot-env@80000 {
                reg = <0x80000 0x10000>;
                label = "u-boot-env";
            };

            kernel@90000 {
                reg = <0x90000 0x770000>;
                label = "kernel";
            };

            rofs@800000 {
                reg = <0x800000 0x1800000>;
                label = "rofs";
            };

            /* Host BIOS region - accessed via eSPI flash channel */
            host-bios@2000000 {
                reg = <0x2000000 0x1000000>;
                label = "host-bios";
            };

            host-bios-backup@3000000 {
                reg = <0x3000000 0x1000000>;
                label = "host-bios-backup";
            };
        };
    };
};
```

### U-Boot Configuration for eDAF

```bash
# U-Boot environment for eDAF systems

# Ensure BMC doesn't interfere with host BIOS region
# Set flash protection for host region during normal operation

# U-Boot defconfig additions:
CONFIG_ASPEED_ESPI=y
CONFIG_ASPEED_ESPI_FLASH=y

# Environment variables
flash_protect=yes
host_bios_offset=0x2000000
host_bios_size=0x1000000
```

### Device Tree for Flash Access Channel

```dts
&espi {
    status = "okay";

    espi_flash: espi-flash {
        compatible = "aspeed,ast2600-espi-flash";
        status = "okay";

        /* Flash access channel configuration */
        flash-channel-enable;

        /* Address mapping for host flash access */
        /* Host sees flash starting at 0x0, mapped to BMC flash offset */
        flash-mafs-mode;  /* Master Attached Flash Sharing */

        /* Or SAF mode for more control */
        /* flash-saf-mode; */
    };
};
```

### eDAF Troubleshooting

**Issue: Host fails to boot (no BIOS execution)**

```bash
# 1. Verify eSPI flash channel is enabled
cat /sys/bus/platform/devices/*.espi-flash/status

# 2. Check flash access channel negotiation
dmesg | grep -i "espi.*flash"
# Look for "flash channel enabled"

# 3. Verify host BIOS region is accessible
hexdump -C /dev/mtd/host-bios | head
# Should show valid BIOS header (not 0xFF)

# 4. Check eSPI timing
# Host may request flash before BMC is ready
# Verify BMC boot timing vs host release

# 5. Monitor flash access
echo 1 > /sys/kernel/debug/aspeed-espi-flash/trace
cat /sys/kernel/debug/aspeed-espi-flash/trace
```

**Issue: Flash corruption or read errors**

```bash
# Check for SPI flash errors
dmesg | grep -i spi
dmesg | grep -i mtd

# Verify flash chip detection
cat /sys/class/mtd/mtd*/name
cat /sys/class/mtd/mtd*/size

# Test flash read
dd if=/dev/mtd/host-bios of=/tmp/bios.bin bs=4096 count=1
hexdump -C /tmp/bios.bin
```

---

## Kernel Drivers & Device Tree

### ASPEED eSPI Kernel Drivers

| Driver | Module | Purpose |
|--------|--------|---------|
| `aspeed-espi-ctrl` | aspeed_espi | Main eSPI controller |
| `aspeed-espi-vw` | aspeed_espi_vw | Virtual wire channel |
| `aspeed-espi-oob` | aspeed_espi_oob | OOB message channel |
| `aspeed-espi-flash` | aspeed_espi_flash | Flash access channel |
| `aspeed-espi-peri` | aspeed_espi_peri | Peripheral channel |

### Kernel Configuration Options

```kconfig
# Main eSPI support
CONFIG_ASPEED_ESPI=y

# Individual channel support
CONFIG_ASPEED_ESPI_PERIPHERAL=y
CONFIG_ASPEED_ESPI_VW=y
CONFIG_ASPEED_ESPI_OOB=y
CONFIG_ASPEED_ESPI_FLASH=y

# Debug options
CONFIG_ASPEED_ESPI_DEBUG=y
```

### Complete Device Tree Example

```dts
// Complete ASPEED AST2600 eSPI configuration

/ {
    compatible = "aspeed,ast2600";

    /* eSPI pin configuration */
    pinctrl {
        espi_default: espi_default {
            function = "ESPI";
            groups = "ESPI";
        };
    };
};

&espi {
    status = "okay";
    pinctrl-names = "default";
    pinctrl-0 = <&espi_default>;

    /* eSPI clock and timing */
    espi,clock-frequency = <66000000>;  /* 66 MHz */

    /* Peripheral channel */
    espi_peri: espi-peripheral {
        compatible = "aspeed,ast2600-espi-peripheral";
        status = "okay";

        /* I/O address decoding */
        io-addr = <0x60 0x64>;  /* KCS interface */
        io-addr = <0x80>;       /* POST code port */

        /* Memory-mapped regions */
        mmio-addr = <0xfed1c000 0x1000>;  /* HECI */
    };

    /* Virtual wire channel */
    espi_vw: espi-vw {
        compatible = "aspeed,ast2600-espi-vw";
        status = "okay";

        gpio-controller;
        #gpio-cells = <2>;
        gpio-line-names =
            "espi-vw-slp-s3",
            "espi-vw-slp-s4",
            "espi-vw-slp-s5",
            "espi-vw-pltrst",
            "espi-vw-sus-stat",
            "espi-vw-sus-warn",
            "espi-vw-oob-rst-warn",
            "espi-vw-host-rst-warn";
    };

    /* OOB message channel */
    espi_oob: espi-oob {
        compatible = "aspeed,ast2600-espi-oob";
        status = "okay";
    };

    /* Flash access channel */
    espi_flash: espi-flash {
        compatible = "aspeed,ast2600-espi-flash";
        status = "okay";
        flash-mafs-mode;
    };
};
```

### Device Tree Properties Reference

| Property | Type | Description |
|----------|------|-------------|
| `status` | string | "okay" to enable, "disabled" to disable |
| `compatible` | string | Driver matching string |
| `espi,clock-frequency` | u32 | eSPI bus clock in Hz |
| `io-addr` | u32 array | Peripheral channel I/O addresses |
| `mmio-addr` | u32 array | Peripheral channel MMIO regions |
| `gpio-controller` | flag | Enable GPIO interface for VW |
| `flash-mafs-mode` | flag | Master Attached Flash Sharing |
| `flash-saf-mode` | flag | Slave Attached Flash mode |

### Pinmux Configuration

```dts
// ASPEED AST2600 eSPI pinmux

&pinctrl {
    /* eSPI uses dedicated pins on AST2600 */
    /* No explicit pinmux needed for eSPI function */

    /* For AST2500, explicit pinmux may be required */
    espi_pins: espi_pins {
        function = "ESPI";
        groups = "ESPI";
        /* Pins: ESPI_CLK, ESPI_CS#, ESPI_IO[3:0], ESPI_ALERT#, ESPI_RST# */
    };
};
```

---

## Platform-Specific Notes

### Intel Platform Considerations

**Virtual Wire Mapping (Intel PCH):**

| Intel Signal | VW Index | Description |
|--------------|----------|-------------|
| SLP_S3# | 2 | S3 sleep |
| SLP_S4# | 3 | S4 sleep |
| SLP_S5# | 4 | S5 sleep |
| SLP_A# | 5 | Deep sleep |
| PLTRST# | 41 | Platform reset |
| PME# | 65 | Power management event |
| WAKE# | 66 | Wake signal |

**Intel ME/CSME Interaction:**

```bash
# Intel ME may use OOB channel for HECI over eSPI
# Ensure HECI MMIO region is configured in peripheral channel

# Device tree for HECI
espi_peri: espi-peripheral {
    mmio-addr = <0xfed1c000 0x1000>;  /* HECI1 */
    mmio-addr = <0xfed1d000 0x1000>;  /* HECI2 */
};
```

### AMD Platform Considerations

**AMD PSP Interaction:**

AMD platforms may have different eSPI behavior due to PSP (Platform Security Processor):

```bash
# AMD may use different VW indices for some signals
# Check AMD BIOS specification for exact mapping

# AMD-specific timing requirements
# PSP initialization may affect eSPI availability
```

**Virtual Wire Differences:**

| AMD Signal | VW Index | Notes |
|------------|----------|-------|
| SLP_S3# | 2 | Same as Intel |
| SLP_S5# | 4 | Same as Intel |
| PLTRST# | 41 | Same as Intel |
| AMD-specific | 64+ | Platform dependent |

### Intel vs AMD Summary

| Aspect | Intel | AMD |
|--------|-------|-----|
| **VW Indices 2-47** | Standard ACPI signals | Generally compatible |
| **VW Indices 64+** | Vendor-specific | Vendor-specific |
| **Flash Channel** | Supported | Supported |
| **OOB Channel** | HECI tunneling | PSP communication |
| **Timing** | ME initialization | PSP initialization |

---

## Troubleshooting

### Step-by-Step eSPI Debugging

```bash
# 1. Verify eSPI controller detected
dmesg | grep -i espi
# Expected: "aspeed-espi XXXXX: eSPI controller initialized"

# 2. Check eSPI negotiation
cat /sys/bus/platform/devices/*.espi/capabilities
# Shows negotiated channels and frequencies

# 3. Verify channel status
for ch in vw oob flash peripheral; do
    echo "=== $ch channel ==="
    cat /sys/bus/platform/devices/*espi-$ch/status 2>/dev/null
done

# 4. Check for errors
dmesg | grep -i "espi.*error\|espi.*fail"

# 5. Monitor eSPI activity
cat /proc/interrupts | grep espi
```

### Common Failure Modes

| Symptom | Possible Cause | Resolution |
|---------|----------------|------------|
| No eSPI in dmesg | Driver not loaded | Check kernel config |
| Channel not enabled | Negotiation failed | Check host eSPI config |
| VW signals stuck | Polarity mismatch | Verify device tree |
| Flash timeouts | Timing issues | Check clock frequency |
| Host boot failure | eDAF not ready | Verify BMC boot timing |

### Relevant Log Messages

```bash
# Successful initialization
aspeed-espi: eSPI controller initialized
aspeed-espi: Channel capabilities: VW OOB Flash Peripheral
aspeed-espi-vw: Virtual wire channel enabled

# Common errors
aspeed-espi: Timeout waiting for channel enable
aspeed-espi: eSPI reset detected
aspeed-espi-flash: Flash read timeout
```

### Debug Interfaces

**Sysfs:**

```bash
# eSPI controller status
/sys/bus/platform/devices/*.espi/
├── capabilities       # Negotiated capabilities
├── enabled           # Controller enable status
├── frequency         # Operating frequency
└── status            # Overall status

# Per-channel status
/sys/bus/platform/devices/*.espi-vw/
├── status            # Channel status
└── vw_gpio/          # GPIO interface for VW
```

**Debugfs:**

```bash
# Enable debugfs (if not mounted)
mount -t debugfs none /sys/kernel/debug

# eSPI debug info
/sys/kernel/debug/aspeed-espi/
├── registers         # Register dump
├── statistics        # Transaction counters
└── trace            # Transaction trace (if enabled)

# Enable tracing
echo 1 > /sys/kernel/debug/aspeed-espi/trace_enable
cat /sys/kernel/debug/aspeed-espi/trace
```

### Reading eSPI Status Registers

```bash
# ASPEED AST2600 eSPI registers (base 0x1E6EE000)
# Use with caution - direct register access

# eSPI Control Register
devmem 0x1E6EE000

# eSPI Interrupt Status
devmem 0x1E6EE008

# eSPI Interrupt Enable
devmem 0x1E6EE00C

# Virtual Wire Status
devmem 0x1E6EE080

# Flash Channel Status
devmem 0x1E6EE0C0
```

---

## References

### Specifications

- [Intel eSPI Interface Base Specification](https://www.intel.com/content/www/us/en/content-details/841685/enhanced-serial-peripheral-interface-espi-interface-base-specification-for-client-and-server-platforms.html) - Official eSPI protocol specification
- [Intel eSPI Specification PDF (Rev 1.6)](https://cdrdv2-public.intel.com/841685/841685_ESPI_IBS_TS_Rev_1_6.pdf) - Direct PDF download

### Kernel Documentation

- [Linux SPI Documentation](https://www.kernel.org/doc/html/latest/spi/) - General SPI subsystem
- [ASPEED eSPI Driver Patches](https://lore.kernel.org/linux-arm-kernel/20220516005412.4844-4-chiawei_wang@aspeedtech.com/) - Kernel mailing list

### OpenBMC Resources

- [OpenBMC Kernel](https://github.com/openbmc/linux) - ASPEED eSPI drivers in drivers/soc/aspeed/
- [ASPEED SDK](https://github.com/AspeedTech-BMC/openbmc) - Vendor examples and reference implementations

---

{: .note }
**Tested on**: ASPEED AST2500/AST2600 EVB with Intel and AMD host platforms
