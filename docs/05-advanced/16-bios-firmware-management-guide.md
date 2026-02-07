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

### External Documentation
- [DMTF Redfish Bios Resource (DSP0268)](https://www.dmtf.org/standards/redfish)
- [ASPEED AST2600 SPI Controller Documentation](https://www.aspeedtech.com/)

---

{: .note }
**Tested on**: QEMU ast2600-evb, OpenBMC commit `497ca5d`
Last updated: 2026-02-06
