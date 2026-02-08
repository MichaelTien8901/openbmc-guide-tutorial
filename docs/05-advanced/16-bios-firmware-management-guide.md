---
layout: default
title: BIOS Firmware Management
parent: Advanced Topics
nav_order: 16
difficulty: intermediate
prerequisites:
  - firmware-update-guide
  - redfish-guide
last_modified_date: 2026-02-06
---

# BIOS Firmware Management
{: .no_toc }

Manage host BIOS/UEFI firmware on OpenBMC -- flash updates via SPI with GPIO mux control, BIOS configuration through biosconfig_manager, and multi-host firmware coordination.
{: .fs-6 .fw-300 }

## Table of Contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

## Overview

OpenBMC provides a complete framework for managing host BIOS firmware from the BMC. This includes flashing BIOS images to the host SPI flash, reading and modifying BIOS configuration settings remotely, and coordinating firmware updates across multi-host platforms.

The BMC accesses host BIOS flash through an SPI connection controlled by a GPIO multiplexer. When the host is powered off, the BMC asserts GPIO lines to route the SPI bus to itself, performs the flash operation, then releases the bus back to the host. This out-of-band access enables firmware recovery even when the host is unbootable.

BIOS configuration management uses the `biosconfig_manager` service, which exposes BIOS settings through D-Bus and the Redfish `Bios` resource. Administrators can read current settings, stage changes as pending attributes, and apply them on the next host boot -- all without physically accessing the machine or entering the BIOS setup menu.

**Key concepts covered:**
- SPI flash access with GPIO mux switching (obmc-flash-bios)
- Redfish UpdateService for BIOS image uploads
- biosconfig_manager for remote BIOS configuration
- PLDM Type 3 (DSP0247) BIOS Control and Configuration — BIOS tables, pldmtool, attribute JSON
- Pending attributes and apply-on-next-boot workflow
- Multi-host firmware management patterns

---

## Architecture

### BIOS Flash Update Flow

The BMC updates host BIOS firmware by taking control of the SPI bus through a GPIO multiplexer, writing the image to flash, and releasing the bus back to the host processor.

```
┌───────────────────────────────────────────────────────────────┐
│               BIOS Flash Update Architecture                  │
├───────────────────────────────────────────────────────────────┤
│                                                               │
│   Update Interfaces                                           │
│   (Redfish UpdateSvc / IPMI OEM / CLI pflash / WebUI)         │
│                          │                                    │
│                          ▼                                    │
│   ┌──────────────────────────────────────────────────────┐    │
│   │     phosphor-bmc-code-mgmt (Host ItemUpdater)        │    │
│   │     ImageManager ─▶ Activation ─▶ Version (D-Bus)    │    │
│   └──────────────────────────┬───────────────────────────┘    │
│                              ▼                                │
│   ┌──────────────────────────────────────────────────────┐    │
│   │                   obmc-flash-bios                    │    │
│   │  1. Assert GPIO mux  ──▶  Route SPI to BMC           │    │
│   │  2. flashcp / pflash  ──▶  Write image to flash      │    │
│   │  3. Release GPIO mux ──▶  Route SPI to Host          │    │
│   └──────────────────────────┬───────────────────────────┘    │
│                              ▼                                │
│   ┌──────────────────────────────────────────────────────┐    │
│   │  Host SPI Flash: Descriptor | BIOS (8-16 MB) | ME/PSP│    │
│   └──────────────────────────────────────────────────────┘    │
│                                                               │
└───────────────────────────────────────────────────────────────┘
```

### BIOS Configuration Flow

The `biosconfig_manager` stores BIOS attributes on D-Bus and exposes them through Redfish. Pending changes are applied by the host BIOS on the next boot cycle.

```
 Redfish /Bios ──┐                   ┌── Host BIOS (reads on boot)
 busctl / D-Bus ─┤   D-Bus calls     │
                 ▼                   │
       ┌─────────────────────────┐   │
       │   biosconfig_manager    │   │
       │                         │   │
       │  BaseBIOSTable (current)│───┘  Populated by host during POST
       │  PendingAttributes      │◀──── Set by admin, read by host
       │  ResetBiosSettings      │
       └─────────────────────────┘
```

### D-Bus Interfaces

| Interface | Object Path | Description |
|-----------|-------------|-------------|
| `xyz.openbmc_project.BIOSConfig.Manager` | `/xyz/openbmc_project/bios_config/manager` | BIOS configuration management |
| `xyz.openbmc_project.Software.Version` | `/xyz/openbmc_project/software/<id>` | BIOS firmware version tracking |
| `xyz.openbmc_project.Software.Activation` | `/xyz/openbmc_project/software/<id>` | BIOS update activation control |

### Key Dependencies

- **phosphor-bmc-code-mgmt**: Core firmware management with Host ItemUpdater for BIOS flash operations.
- **obmc-flash-bios**: Shell scripts and systemd services that control GPIO mux switching and invoke flash tools.
- **biosconfig_manager**: D-Bus service that stores BIOS attributes and exposes them through the Redfish Bios resource.
- **bmcweb**: Redfish server that maps `UpdateService` and `Systems/{id}/Bios` endpoints to D-Bus calls.

---

## BIOS Flash Update

### SPI Flash Access with GPIO Mux

The BMC and host processor share access to the host SPI flash through a hardware multiplexer. The BMC controls which device owns the SPI bus by asserting or deasserting GPIO lines.

{: .warning }
**Never flash BIOS while the host is running.** The host must be powered off before the BMC takes control of the SPI bus. Flashing while the host is active corrupts the running firmware and can damage the flash device.

#### GPIO Mux Configuration

Define the GPIO lines and flash device in your machine layer's device tree:

```dts
/* AST2600 device tree: GPIO mux for host SPI */
gpio_bios_mux: bios-mux {
    compatible = "gpio-mux";
    gpios = <&gpio0 ASPEED_GPIO(AA, 0) GPIO_ACTIVE_HIGH>;
    /* HIGH = BMC owns SPI, LOW = Host owns SPI */
};

&fmc {
    status = "okay";
    flash@1 {
        /* Host BIOS SPI flash behind mux */
        status = "okay";
        spi-max-frequency = <50000000>;
    };
};
```

#### obmc-flash-bios Service

The `obmc-flash-bios` systemd service manages the GPIO switching and flash operations. The script follows a strict sequence: verify host power state, assert the mux, write flash, release the mux.

```bash
#!/bin/bash
# obmc-flash-bios -- Flash BIOS image to host SPI
BIOS_MTD="/dev/mtd/bios"
GPIO_MUX="/sys/class/gpio/gpio<N>/value"

# Verify host is powered off
host_state=$(busctl get-property xyz.openbmc_project.State.Host \
    /xyz/openbmc_project/state/host0 \
    xyz.openbmc_project.State.Host CurrentHostState | awk '{print $2}')
[ "$host_state" != '"xyz.openbmc_project.State.Host.HostState.Off"' ] && exit 1

echo 1 > "$GPIO_MUX"       # Assert GPIO mux -- route SPI to BMC
sleep 0.5
flashcp -v "$1" "$BIOS_MTD" # Flash the BIOS image
rc=$?
echo 0 > "$GPIO_MUX"       # Release GPIO mux -- route SPI to Host
exit $rc
```

### Redfish UpdateService

Upload a BIOS image through the Redfish UpdateService endpoint. The BMC validates the image, triggers the flash operation, and tracks progress through a task resource.

```bash
# Upload BIOS firmware image via Redfish
curl -k -u root:0penBmc \
    -X POST \
    -H "Content-Type: application/octet-stream" \
    --data-binary @bios-firmware.bin \
    https://${BMC_IP}/redfish/v1/UpdateService
```

{: .tip }
For large BIOS images (16 MB+), use the `MultipartHttpPushUri` endpoint with a target to avoid HTTP timeout issues.

```bash
# Multipart upload targeting the BIOS resource
curl -k -u root:0penBmc \
    -X POST \
    -F 'UpdateParameters={"Targets":["/redfish/v1/Systems/system/Bios"]};type=application/json' \
    -F 'UpdateFile=@bios-firmware.bin;type=application/octet-stream' \
    https://${BMC_IP}/redfish/v1/UpdateService/update

# Monitor update progress
curl -k -u root:0penBmc \
    https://${BMC_IP}/redfish/v1/TaskService/Tasks/0

# Verify BIOS firmware inventory after update
curl -k -u root:0penBmc \
    https://${BMC_IP}/redfish/v1/UpdateService/FirmwareInventory/bios
```

### Build-Time Configuration

Enable host BIOS upgrade support in your Yocto configuration:

```bitbake
# In your machine .conf or local.conf
EXTRA_OEMESON:pn-phosphor-bmc-code-mgmt += " \
    -Dhost-bios-upgrade=enabled \
"

IMAGE_INSTALL:append = " \
    phosphor-software-manager \
    obmc-flash-bios \
"
```

---

## BIOS Configuration with biosconfig_manager

The `biosconfig_manager` service provides remote BIOS configuration management. It stores BIOS attribute definitions and their current values on the BMC, allows administrators to stage pending changes, and signals the host firmware to apply them on the next boot.

### How It Works

1. The host BIOS populates the BMC with its current attribute table (via IPMI or PLDM) during boot.
2. The BMC stores these as `BaseBIOSTable` attributes on D-Bus.
3. An administrator sets `PendingAttributes` through Redfish or D-Bus.
4. On the next host boot, the BIOS reads pending attributes from the BMC and applies them.
5. The BIOS reports updated current values back to the BMC.

{: .note }
The `biosconfig_manager` does not flash BIOS firmware. It manages BIOS *settings* (boot order, memory timing, virtualization, security features). For BIOS *image* updates, use the UpdateService workflow described above.

### D-Bus Operations

#### Reading Current BIOS Attributes

```bash
# List the BaseBIOSTable (all current BIOS attributes)
busctl get-property xyz.openbmc_project.BIOSConfigManager \
    /xyz/openbmc_project/bios_config/manager \
    xyz.openbmc_project.BIOSConfig.Manager \
    BaseBIOSTable
```

Each `BaseBIOSTable` entry contains:

| Field | Type | Description |
|-------|------|-------------|
| `AttributeType` | string | `Enumeration`, `String`, `Integer`, `Boolean` |
| `ReadOnly` | boolean | Whether the attribute can be modified |
| `DisplayName` | string | Human-readable name |
| `CurrentValue` | variant | Current setting value |
| `DefaultValue` | variant | Factory default value |
| `Options` | array | Valid values for enumeration types |

#### Setting Pending Attributes

```bash
# Stage a BIOS attribute change (applied on next boot)
busctl set-property xyz.openbmc_project.BIOSConfigManager \
    /xyz/openbmc_project/bios_config/manager \
    xyz.openbmc_project.BIOSConfig.Manager \
    PendingAttributes a{s\(sv\)} 2 \
    "HyperThreading" "s" "Enabled" \
    "VTx" "s" "Enabled"

# Reset all BIOS settings to factory defaults
busctl call xyz.openbmc_project.BIOSConfigManager \
    /xyz/openbmc_project/bios_config/manager \
    xyz.openbmc_project.BIOSConfig.Manager \
    ResetBiosSettings s \
    "xyz.openbmc_project.BIOSConfig.Manager.ResetFlag.FactoryDefaults"
```

### Redfish Bios Resource

The Redfish `Bios` resource at `/redfish/v1/Systems/system/Bios` maps directly to the `biosconfig_manager` D-Bus interface.

```bash
# Read current BIOS attributes
curl -k -u root:0penBmc \
    https://${BMC_IP}/redfish/v1/Systems/system/Bios

# Stage pending BIOS attribute changes (applied on next boot)
curl -k -u root:0penBmc \
    -X PATCH \
    -H "Content-Type: application/json" \
    -d '{
        "Attributes": {
            "BootOrder": "PXE,HDD,USB",
            "QuietBoot": "Disabled"
        }
    }' \
    https://${BMC_IP}/redfish/v1/Systems/system/Bios/Settings

# Reset all BIOS settings to factory defaults
curl -k -u root:0penBmc \
    -X POST \
    -H "Content-Type: application/json" \
    -d '{"ResetType": "ResetAll"}' \
    https://${BMC_IP}/redfish/v1/Systems/system/Bios/Actions/Bios.ResetBios
```

{: .tip }
After staging pending attributes, reboot the host to apply changes. The BIOS reads pending attributes from the BMC during POST and clears them after successful application.

### BIOS Configuration JSON Schema

Define your platform's BIOS attributes in a JSON file that `biosconfig_manager` loads at startup:

```json
{
    "BaseBIOSTable": {
        "BootOrder": {
            "AttributeType": "Enumeration",
            "ReadOnly": false,
            "DisplayName": "Boot Order",
            "CurrentValue": "HDD,PXE,USB",
            "DefaultValue": "HDD,PXE,USB",
            "Options": ["HDD,PXE,USB", "PXE,HDD,USB", "USB,HDD,PXE"]
        },
        "HyperThreading": {
            "AttributeType": "Enumeration",
            "ReadOnly": false,
            "DisplayName": "Hyper-Threading",
            "CurrentValue": "Enabled",
            "DefaultValue": "Enabled",
            "Options": ["Enabled", "Disabled"]
        }
    }
}
```

See the complete example at [examples/bios-config/]({{ site.baseurl }}/examples/bios-config/).

---

## PLDM-Based BIOS Configuration (DSP0247)

For platforms that use PLDM (Platform Level Data Model) between the BMC and host, BIOS configuration is handled through **PLDM Type 3 — BIOS Control and Configuration**, defined in DMTF specification [DSP0247](https://www.dmtf.org/sites/default/files/standards/documents/DSP0247_1.0.0.pdf). This is the modern alternative to IPMI-based BIOS attribute exchange and is used on IBM POWER, ARM, and other PLDM-enabled platforms.

### How PLDM BIOS Configuration Works

The host BIOS and the BMC's `pldmd` daemon exchange BIOS attributes using three PLDM BIOS tables and a set of PLDM commands. The `pldmd` daemon acts as the bridge between the host and the `biosconfig_manager` D-Bus service.

```
┌───────────────────────────────────────────────────────────────────┐
│             PLDM BIOS Configuration Data Flow                     │
├───────────────────────────────────────────────────────────────────┤
│                                                                   │
│  Admin (Redfish/CLI)                                              │
│       │                                                           │
│       ▼                                                           │
│  ┌──────────────┐   D-Bus    ┌──────────────┐   PLDM/MCTP         │
│  │ bmcweb       │──────────▶│ biosconfig   │◀────────────┐        │
│  │ /Bios        │           │ _manager     │             │        │
│  └──────────────┘           │              │             │        │
│                             │ BaseBIOSTable│             │        │
│                             │ Pending      │             │        │
│                             │ Attributes   │             │        │
│                             └──────┬───────┘             │        │
│                                    │ D-Bus               │        │
│                                    ▼                     │        │
│                             ┌──────────────┐             │        │
│                             │ pldmd        │─────────────┘        │
│                             │              │                      │
│                             │ BIOS Tables: │   PLDM over MCTP     │
│                             │  - String    │◀────────────────┐    │
│                             │  - Attribute │                 │    │
│                             │  - Value     │                 │    │
│                             └──────────────┘                 │    │
│                                                              │    │
│                             ┌──────────────┐                 │    │
│                             │  Host BIOS   │─────────────────┘    │
│                             │  (PLDM       │                      │
│                             │   terminus)  │                      │
│                             └──────────────┘                      │
│                                                                   │
└───────────────────────────────────────────────────────────────────┘
```

### The Three PLDM BIOS Tables

PLDM BIOS uses three interrelated tables to represent all BIOS configuration data:

| Table | PLDM Table Type | Purpose |
|-------|----------------|---------|
| **String Table** | 0 | Dictionary of all strings used by attributes (names, option labels, help text) |
| **Attribute Table** | 1 | Schema for each attribute: type (enum/integer/string), constraints, default values |
| **Attribute Value Table** | 2 | Current runtime values for each attribute |

These tables are exchanged between the host BIOS and the BMC using PLDM commands:

| PLDM Command | Direction | Description |
|-------------|-----------|-------------|
| `GetBIOSTable` | BMC → Host | BMC requests a BIOS table from the host |
| `SetBIOSTable` | Host → BMC | Host sends a complete BIOS table to the BMC |
| `GetBIOSAttributeCurrentValueByHandle` | BMC → Host | Read a single attribute's current value |
| `SetBIOSAttributeCurrentValue` | Host → BMC or BMC → Host | Update a single attribute value |

### PLDM BIOS Boot Sequence

```
┌──────────────────────────────────────────────────────────────────┐
│               PLDM BIOS Configuration Timeline                   │
├──────────────────────────────────────────────────────────────────┤
│                                                                  │
│   HOST BIOS                              BMC (pldmd)             │
│   ─────────                              ──────────              │
│      │                                      │                    │
│  1.  │── SetBIOSTable (String)  ──────────▶ │  Store string      │
│      │                                      │  table             │
│  2.  │── SetBIOSTable (Attribute) ────────▶ │  Store attribute   │
│      │                                      │  definitions       │
│  3.  │── SetBIOSTable (AttrValue) ────────▶ │  Store current     │
│      │                                      │  values            │
│      │                                      │                    │
│      │                             pldmd populates               │
│      │                             BaseBIOSTable on D-Bus        │
│      │                                      │                    │
│  4.  │◀── GetBIOSTable (Pending) ────────── │  Send any pending  │
│      │                                      │  attribute changes │
│  5.  │  Apply pending attributes            │                    │
│      │                                      │                    │
│  6.  │── SetBIOSAttributeCurrentValue ────▶ │  Report updated    │
│      │                                      │  values            │
│      │                                      │                    │
│  7.  │  Continue POST                       │  Clear pending     │
│      │                                      │  attributes        │
│      ▼                                      ▼                    │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘
```

### PLDM BIOS Attribute JSON Configuration

For PLDM-based systems, OEM vendors define BIOS attributes in JSON files that `pldmd` parses to initialize the `BaseBIOSTable`. These files define the attribute schema — `pldmd` converts them to PLDM BIOS table format.

```json
{
    "entries": [
        {
            "attribute_type": "enum",
            "attribute_name": "HyperThreading",
            "possible_values": ["Enabled", "Disabled"],
            "default_values": ["Enabled"],
            "display_name": "Hyper-Threading Technology",
            "help_text": "Enable or disable CPU Hyper-Threading",
            "read_only": false,
            "dbus": {
                "object_path": "/xyz/openbmc_project/bios_config/manager",
                "interface": "xyz.openbmc_project.BIOSConfig.Manager",
                "property_name": "HyperThreading",
                "property_type": "string"
            }
        },
        {
            "attribute_type": "integer",
            "attribute_name": "MemoryFrequency",
            "lower_bound": 1600,
            "upper_bound": 4800,
            "scalar_increment": 400,
            "default_value": 3200,
            "display_name": "Memory Operating Frequency (MHz)",
            "help_text": "Set DDR memory operating frequency",
            "read_only": false
        },
        {
            "attribute_type": "string",
            "attribute_name": "AssetTag",
            "string_type": "ASCII",
            "minimum_string_length": 0,
            "maximum_string_length": 64,
            "default_string": "",
            "display_name": "System Asset Tag",
            "read_only": false
        }
    ]
}
```

Install this file in your machine layer:

```bitbake
# meta-<machine>/recipes-phosphor/pldm/pldm_%.bbappend
FILESEXTRAPATHS:prepend := "${THISDIR}/${PN}:"
SRC_URI += "file://bios_attrs.json"

do_install:append() {
    install -d ${D}${datadir}/pldm/bios
    install -m 0644 ${WORKDIR}/bios_attrs.json \
        ${D}${datadir}/pldm/bios/
}
```

### Using pldmtool for BIOS Operations

The `pldmtool` CLI on the BMC provides direct access to PLDM BIOS commands for debugging and testing.

```bash
# Get the BIOS String Table (type 0)
pldmtool bios GetBIOSTable -t 0

# Get the BIOS Attribute Table (type 1) -- shows attribute definitions
pldmtool bios GetBIOSTable -t 1

# Get the BIOS Attribute Value Table (type 2) -- shows current values
pldmtool bios GetBIOSTable -t 2

# Get a single attribute's current value by handle
pldmtool bios GetBIOSAttributeCurrentValueByHandle -a HyperThreading

# Set a BIOS attribute value
pldmtool bios SetBIOSAttributeCurrentValue -a HyperThreading -d Disabled
```

{: .tip }
Use `pldmtool bios GetBIOSTable -t 1` to discover all available BIOS attributes and their valid values. This is the PLDM equivalent of viewing the BIOS setup menu.

### PLDM vs IPMI for BIOS Configuration

| Aspect | IPMI (Traditional) | PLDM (Modern) |
|--------|-------------------|---------------|
| **Transport** | IPMB / KCS / BT | MCTP over I3C, SMBus, or PCIe VDM |
| **Specification** | Vendor-specific OEM commands | DMTF DSP0247 (standardized) |
| **Attribute discovery** | Not standardized — requires vendor docs | Self-describing via PLDM BIOS tables |
| **Data model** | Flat key-value | Typed attributes (enum, int, string) with constraints |
| **Pending attributes** | Vendor-dependent | Standardized pending table exchange |
| **Security** | No built-in auth | SPDM integration possible over MCTP |
| **Platforms** | Legacy x86, older BMC designs | IBM POWER, ARM SBMR, OCP servers |

{: .note }
Both IPMI and PLDM ultimately populate the same `biosconfig_manager` D-Bus interface. Redfish consumers do not need to know which protocol the host uses — the Redfish `/Systems/system/Bios` endpoint works identically regardless of the underlying transport.

### Troubleshooting PLDM BIOS

**BIOS tables not populated after host boot:**
```bash
# Check if pldmd discovered the host as a PLDM terminus
pldmtool base GetTID

# Check if BIOS tables were received
journalctl -u pldmd -f | grep -i bios

# Verify MCTP connectivity to the host
busctl tree xyz.openbmc_project.MCTP
```

**Pending attributes not reaching the host:**
```bash
# Verify pending attributes are set on D-Bus
busctl get-property xyz.openbmc_project.BIOSConfigManager \
    /xyz/openbmc_project/bios_config/manager \
    xyz.openbmc_project.BIOSConfig.Manager \
    PendingAttributes

# Check pldmd logs for pending attribute transfer
journalctl -u pldmd --no-pager | grep -i pending
```

**Attribute type mismatch errors:**
Ensure your `bios_attrs.json` matches the host BIOS attribute types exactly. An enum attribute on the host cannot be set with an integer value from the BMC. Use `pldmtool bios GetBIOSTable -t 1` to verify attribute definitions.

---

## Multi-Host Firmware Management

In multi-host platforms (blade servers, multi-node chassis), the BMC manages BIOS firmware for multiple host processors independently. Each host has its own SPI flash, GPIO mux, and D-Bus object path.

### Multi-Host D-Bus Layout

Each host gets a separate D-Bus object path for both firmware management and BIOS configuration:

| Host | Firmware Object | BIOSConfig Object |
|------|----------------|-------------------|
| Host 0 | `/xyz/openbmc_project/software/host0_bios` | `/xyz/openbmc_project/bios_config/manager0` |
| Host 1 | `/xyz/openbmc_project/software/host1_bios` | `/xyz/openbmc_project/bios_config/manager1` |
| Host N | `/xyz/openbmc_project/software/hostN_bios` | `/xyz/openbmc_project/bios_config/managerN` |

### Redfish Multi-Host Endpoints

```bash
# Access BIOS settings for a specific host
curl -k -u root:0penBmc \
    https://${BMC_IP}/redfish/v1/Systems/system0/Bios
curl -k -u root:0penBmc \
    https://${BMC_IP}/redfish/v1/Systems/system1/Bios

# Update BIOS firmware for a specific host
curl -k -u root:0penBmc \
    -X POST \
    -F 'UpdateParameters={"Targets":["/redfish/v1/Systems/system1/Bios"]};type=application/json' \
    -F 'UpdateFile=@bios-firmware.bin;type=application/octet-stream' \
    https://${BMC_IP}/redfish/v1/UpdateService/update
```

### Multi-Host Build Configuration

```bitbake
# In your machine .conf for multi-host support
OBMC_HOST_INSTANCES = "0 1 2 3"
OBMC_HOST_BIOS_FLASH_INSTANCES = "0 1 2 3"
BIOS_MUX_GPIO_host0 = "AA0"
BIOS_MUX_GPIO_host1 = "AA1"
BIOS_MUX_GPIO_host2 = "AA2"
BIOS_MUX_GPIO_host3 = "AA3"
```

{: .note }
Never flash two hosts simultaneously if they share a SPI controller. The GPIO mux ensures only one host flash is accessible at a time, so your update orchestration must serialize flash operations.

---

## Porting Guide

Follow these steps to enable BIOS firmware management on your platform.

### Step 1: Prerequisites

Ensure you have:
- [ ] A working OpenBMC build for your platform
- [ ] GPIO mux hardware between BMC SPI controller and host SPI flash
- [ ] Knowledge of your platform's GPIO pin assignments for the mux
- [ ] Host BIOS that supports BMC-based configuration (IPMI or PLDM interface)

### Step 2: Configure Device Tree

Add SPI flash and GPIO mux definitions to your machine device tree (`meta-<machine>/recipes-kernel/linux/files/<machine>.dts`). Enable `flash@1` under `&fmc` for the host BIOS SPI flash behind the GPIO mux, as shown in the GPIO Mux Configuration section above.

### Step 3: Create Flash Scripts

Add the `obmc-flash-bios` script and systemd service to your machine layer:

```bitbake
# meta-<machine>/recipes-phosphor/flash/obmc-flash-bios.bbappend
FILESEXTRAPATHS:prepend := "${THISDIR}/${PN}:"
SRC_URI += "file://obmc-flash-bios file://obmc-flash-bios@.service"
do_install:append() {
    install -d ${D}${sbindir}
    install -m 0755 ${WORKDIR}/obmc-flash-bios ${D}${sbindir}/
    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${WORKDIR}/obmc-flash-bios@.service ${D}${systemd_system_unitdir}/
}
```

### Step 4: Enable biosconfig_manager

```bitbake
# meta-<machine>/recipes-phosphor/bios/biosconfig-manager.bbappend
FILESEXTRAPATHS:prepend := "${THISDIR}/${PN}:"
SRC_URI += "file://bios-attrs.json"
do_install:append() {
    install -d ${D}${datadir}/biosconfig
    install -m 0644 ${WORKDIR}/bios-attrs.json ${D}${datadir}/biosconfig/
}
```

### Step 5: Verify

1. Build the image: `bitbake obmc-phosphor-image`
2. Check services: `systemctl status xyz.openbmc_project.biosconfig_manager.service`
3. Verify D-Bus: `busctl tree xyz.openbmc_project.BIOSConfigManager`
4. Test Redfish: `curl -k -u root:0penBmc https://localhost/redfish/v1/Systems/system/Bios`

---

## Troubleshooting

### Issue: BIOS Flash Fails with "Device Busy"

**Symptom**: `flashcp` returns "Device or resource busy".

**Cause**: GPIO mux not asserted, or another process holds the MTD device.

**Solution**: Verify the host is off (`obmcutil state`), check the GPIO mux value (`cat /sys/class/gpio/gpio<N>/value` should be `1`), and check for other MTD users (`fuser /dev/mtd/bios`).

### Issue: Pending Attributes Not Applied After Reboot

**Symptom**: Changes staged via `/Bios/Settings` remain pending after host reboot.

**Cause**: Host BIOS does not support the BMC attribute interface, or the IPMI/PLDM channel is misconfigured.

**Solution**: Verify pending attributes are stored on D-Bus (`busctl get-property ... PendingAttributes`), confirm the host BIOS supports the attribute protocol (consult vendor docs), and check `biosconfig_manager` logs (`journalctl -u xyz.openbmc_project.biosconfig_manager.service -f`).

### Issue: Redfish Returns 404 for /Systems/system/Bios

**Symptom**: The Bios resource endpoint returns "ResourceNotFound".

**Cause**: `biosconfig_manager` is not running or has not populated the `BaseBIOSTable`.

**Solution**: Check the service status (`systemctl status xyz.openbmc_project.biosconfig_manager.service`), verify the D-Bus object exists (`busctl introspect xyz.openbmc_project.BIOSConfigManager /xyz/openbmc_project/bios_config/manager`), and ensure the BIOS attribute JSON file is installed at the expected path.

### Debug Commands

```bash
systemctl status obmc-flash-bios@0.service                              # Flash service
journalctl -u xyz.openbmc_project.biosconfig_manager.service --no-pager # Config logs
busctl tree xyz.openbmc_project.BIOSConfigManager                       # D-Bus objects
gpioget gpiochip0 <line_number>                                         # GPIO mux state
cat /proc/mtd                                                           # MTD partitions
obmcutil state                                                          # Host power state
```

---

## References

### Official Resources
- [phosphor-bmc-code-mgmt Repository](https://github.com/openbmc/phosphor-bmc-code-mgmt)
- [biosconfig_manager Repository](https://github.com/openbmc/bios-settings-mgr)
- [D-Bus BIOSConfig Interface](https://github.com/openbmc/phosphor-dbus-interfaces/tree/master/yaml/xyz/openbmc_project/BIOSConfig)
- [OpenBMC Host Firmware Update Documentation](https://github.com/openbmc/docs/blob/master/architecture/code-update/host-code-update.md)

### Related Guides
- [Firmware Update Guide]({% link docs/05-advanced/03-firmware-update-guide.md %})
- [Secure Boot & Image Signing]({% link docs/05-advanced/13-secure-boot-signing-guide.md %})
- [MCTP & PLDM Guide]({% link docs/05-advanced/01-mctp-pldm-guide.md %}) - PLDM transport and sensor monitoring

### External Documentation
- [DMTF Redfish Bios Resource (DSP0268)](https://www.dmtf.org/standards/redfish)
- [PLDM for BIOS Control and Configuration (DSP0247)](https://www.dmtf.org/sites/default/files/standards/documents/DSP0247_1.0.0.pdf)
- [ASPEED AST2600 SPI Controller Documentation](https://www.aspeedtech.com/)
- [OpenBMC Remote BIOS Configuration Design](https://github.com/openbmc/docs/blob/master/designs/remote-bios-configuration.md)

---

{: .note }
**Tested on**: QEMU ast2600-evb, OpenBMC commit `497ca5d`
Last updated: 2026-02-06
