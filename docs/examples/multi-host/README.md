# Multi-Host Configuration Examples

Entity Manager and IPMB configuration files for a 4-host sled platform where a
single BMC manages multiple host processors over dedicated IPMB channels.

> **Reference configurations** -- these JSON files are loaded by Entity Manager
> and ipmb-bridge at runtime on OpenBMC. Adapt the bus numbers, I2C addresses,
> and sensor thresholds to match your hardware.

## Architecture Overview

In a multi-host (sled) platform, one BMC manages multiple independent host CPUs.
Each host has its own dedicated I2C/IPMB bus for out-of-band communication. The
BMC uses IPMB bridges to forward IPMI messages to each host and reads per-host
sensors (temperature, power, status) through those same buses.

```
                        +-----------+
                        |    BMC    |
                        | (AST2600) |
                        +-----+-----+
                              |
            +--------+--------+--------+--------+
            |        |        |        |        |
         I2C Bus 2  Bus 3   Bus 4   Bus 5
            |        |        |        |
        +---+---+ +--+--+ +--+--+ +---+---+
        | Host0 | |Host1| |Host2| | Host3 |
        | Sled0 | |Sled1| |Sled2| | Sled3 |
        +-------+ +-----+ +-----+ +-------+
```

Each host bus carries:
- **IPMB traffic** -- IPMI messages between the BMC and the host's baseboard
  management controller or bridge IC (typically at address `0x20`)
- **Sensor I2C devices** -- temperature sensors (TMP75, TMP421), voltage
  regulators, and FRU EEPROMs attached to the same bus or behind an I2C mux

## Files

| File | Loaded By | Description |
|------|-----------|-------------|
| `entity-manager-4host.json` | Entity Manager | Board definition with per-host IPMB sensors, temperature sensors, and voltage monitors for a 4-sled platform |
| `ipmb-channels.json` | ipmb-bridge (phosphor-ipmi-ipmb) | IPMB channel definitions mapping each host to its I2C bus and slave address |

## How the Pieces Fit Together

### Entity Manager

Entity Manager reads JSON configuration files from `/usr/share/entity-manager/configurations/`.
When the BMC boots, it probes for matching hardware (FRU EEPROMs, GPIO presence
pins) and instantiates the `Exposes` entries as D-Bus objects. Sensor daemons
(`dbus-sensors`) then pick up these objects and start polling hardware.

For a multi-host platform, you define one JSON file containing entries for all
hosts. Each sensor name includes the host index (for example, `Host0 Inlet Temp`,
`Host1 Inlet Temp`) so that sensors appear as distinct D-Bus objects.

### IPMB Bridge

The `ipmb-bridge` daemon (from `phosphor-ipmi-ipmb`) reads its channel
configuration and opens one IPMB channel per host. Each channel maps to a
specific I2C bus and target address. The host IPMI stack sends requests over
IPMB, and the bridge forwards them to the BMC's IPMI daemon for processing.

The channel configuration file is typically installed to
`/usr/share/ipmi-providers/` or passed as a command-line argument to the
ipmb-bridge service.

## Installation

### Entity Manager Configuration

```bash
# Install on BMC (via Yocto recipe or manual copy)
cp entity-manager-4host.json \
    /usr/share/entity-manager/configurations/multi-host-sled.json

# Restart Entity Manager to pick up the new configuration
systemctl restart xyz.openbmc_project.EntityManager
```

### IPMB Bridge Configuration

```bash
# Install the channel configuration
cp ipmb-channels.json /usr/share/ipmi-providers/ipmb-channels.json

# Restart the IPMB bridge
systemctl restart ipmb.service
```

## Yocto Integration

### Bitbake Recipe for Entity Manager Config

```bitbake
# In meta-myplatform/recipes-phosphor/configuration/entity-manager/
# multi-host-entity-config.bb

SUMMARY = "Entity Manager configuration for 4-host sled platform"
LICENSE = "Apache-2.0"
LIC_FILES_CHKSUM = "file://${COREBASE}/meta/files/common-licenses/Apache-2.0;md5=..."
inherit allarch

SRC_URI = "file://multi-host-sled.json"

do_install() {
    install -d ${D}${datadir}/entity-manager/configurations
    install -m 0644 ${WORKDIR}/multi-host-sled.json \
        ${D}${datadir}/entity-manager/configurations/
}

FILES:${PN} = "${datadir}/entity-manager/configurations/*"
```

### Enable IPMB in the Image

```bitbake
# local.conf or machine .conf
IMAGE_INSTALL:append = " \
    phosphor-ipmi-ipmb \
"

# Enable IPMB sensor daemon in dbus-sensors
EXTRA_OEMESON:pn-dbus-sensors = " \
    -Dipmb=enabled \
"
```

## Verification

After deploying the configuration and rebooting:

```bash
# Check that Entity Manager loaded the multi-host configuration
busctl tree xyz.openbmc_project.EntityManager | grep -i host

# Verify IPMB channels are active
systemctl status ipmb.service
journalctl -u ipmb.service --no-pager | tail -20

# List per-host sensors on D-Bus
busctl tree xyz.openbmc_project.HwmonTempSensor | grep Host
busctl tree xyz.openbmc_project.IpmbSensor | grep Host

# Read a specific host sensor
busctl get-property xyz.openbmc_project.HwmonTempSensor \
    /xyz/openbmc_project/sensors/temperature/Host0_Inlet_Temp \
    xyz.openbmc_project.Sensor.Value Value

# Check IPMB connectivity to each host
ipmitool -I ipmb -H 0 raw 0x06 0x01   # Host 0 - Get Device ID
ipmitool -I ipmb -H 1 raw 0x06 0x01   # Host 1 - Get Device ID
ipmitool -I ipmb -H 2 raw 0x06 0x01   # Host 2 - Get Device ID
ipmitool -I ipmb -H 3 raw 0x06 0x01   # Host 3 - Get Device ID
```

## Customization Guide

### Adding More Hosts

To expand from 4 to 8 hosts:

1. Add entries for Host4 through Host7 in `entity-manager-4host.json`,
   following the same pattern with new I2C bus numbers and sensor names
2. Add channels 4 through 7 in `ipmb-channels.json` with the corresponding
   bus and address assignments
3. Verify that your AST2600 device tree enables the additional I2C buses

### Changing I2C Bus Assignments

The bus numbers in these examples (2, 3, 4, 5) assume the AST2600 device tree
assigns those buses to the host sled connectors. If your platform uses different
buses (for example, behind an I2C mux), update:

- The `"Bus"` field in each Entity Manager sensor entry
- The `"bus"` field in each IPMB channel entry
- Your device tree I2C node definitions

### Adding Per-Host Power Monitoring

To add INA230 power monitors per host, add entries like this to the `Exposes`
array in `entity-manager-4host.json`:

```json
{
    "Name": "Host0 Input Power",
    "Type": "INA230",
    "Bus": 2,
    "Address": "0x40",
    "ShuntResistor": 0.002,
    "PowerState": "On",
    "Thresholds": [
        {
            "Direction": "greater than",
            "Name": "upper critical",
            "Severity": 1,
            "Value": 350
        }
    ]
}
```

## Troubleshooting

```bash
# Entity Manager did not load the configuration
# Check for JSON syntax errors
python3 -m json.tool < /usr/share/entity-manager/configurations/multi-host-sled.json

# Check Entity Manager logs for probe failures
journalctl -u xyz.openbmc_project.EntityManager --no-pager | grep -i error

# IPMB bridge cannot communicate with a host
# Verify the I2C bus is enabled in the device tree
ls /dev/i2c-*

# Scan the I2C bus for devices
i2cdetect -y 2    # Should show device at 0x20 (IPMB target)
i2cdetect -y 3
i2cdetect -y 4
i2cdetect -y 5

# Check IPMB bridge logs
journalctl -u ipmb.service -f

# Sensor daemon not picking up IPMB sensors
systemctl status xyz.openbmc_project.IpmbSensor
journalctl -u xyz.openbmc_project.IpmbSensor --no-pager | tail -20
```

## References

- [D-Bus Sensors Guide](../../03-core-services/01-dbus-sensors-guide.md) -- sensor daemon architecture and IPMB sensor configuration
- [Systemd Multi-Host Template Units](../../02-architecture/05-systemd-boot-ordering-guide.md) -- per-host service management
- [Entity Manager Repository](https://github.com/openbmc/entity-manager) -- configuration format documentation
- [phosphor-ipmi-ipmb Repository](https://github.com/openbmc/ipmi-ipmbbridge) -- IPMB bridge daemon source
- [IPMI IPMB Specification](https://www.intel.com/content/www/us/en/products/docs/servers/ipmi/ipmi-second-gen-interface-spec-v2-rev1-1.html)
