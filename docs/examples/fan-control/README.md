# Fan Control Configuration Examples

Example configurations for phosphor-pid-control (swampd).

## Files

| File | Description |
|------|-------------|
| `zone-config.json` | Direct swampd config: sensors, zone, thermal + fan PIDs |
| `multi-zone-config.json` | Multi-zone: separate CPU and system fan zones |
| `stepwise-config.json` | Table-based stepwise control (no PID tuning needed) |
| `entity-manager-fan.json` | Entity Manager config: zone + thermal + fan PIDs |

## Two Configuration Methods

phosphor-pid-control supports two config paths:

### Method 1: Direct JSON (simple, for development)

Place `config.json` directly in swampd's config directory. phosphor-pid-control reads it at startup.

```bash
# Copy to BMC (QEMU port 2222)
scp -P 2222 zone-config.json root@localhost:/usr/share/swampd/config.json

# Restart fan control
ssh -p 2222 root@localhost systemctl restart phosphor-pid-control
```

**File**: `zone-config.json` contains everything: sensor D-Bus paths, zones, and PIDs.
**Install path**: `/usr/share/swampd/config.json`

### Method 2: Entity Manager (recommended for production)

Entity Manager loads your JSON, evaluates the `Probe` field to determine if it
applies to the current hardware, and publishes the config to D-Bus.
phosphor-pid-control reads its config from D-Bus (not from the file directly).

```bash
# Copy to Entity Manager configurations directory
scp -P 2222 entity-manager-fan.json \
    root@localhost:/usr/share/entity-manager/configurations/

# Restart Entity Manager (triggers phosphor-pid-control reload)
ssh -p 2222 root@localhost systemctl restart xyz.openbmc_project.EntityManager
```

**File**: `entity-manager-fan.json` uses `Exposes` array with `Type: Pid.Zone`
and `Type: Pid` entries.
**Install path**: `/usr/share/entity-manager/configurations/<name>.json`

For Yocto integration, add via a bbappend:

```bash
# meta-myplatform/recipes-phosphor/configuration/entity-manager/entity-manager_%.bbappend
FILESEXTRAPATHS:prepend := "${THISDIR}/files:"
SRC_URI += "file://my-board-fan-control.json"

do_install:append() {
    install -d ${D}${datadir}/entity-manager/configurations
    install -m 0444 ${WORKDIR}/my-board-fan-control.json \
        ${D}${datadir}/entity-manager/configurations/
}
```

### Key Differences

| | Direct JSON | Entity Manager |
|---|---|---|
| Config file location | `/usr/share/swampd/config.json` | `/usr/share/entity-manager/configurations/*.json` |
| Includes sensor D-Bus paths | Yes (`sensors` array) | No (Entity Manager resolves sensors) |
| Hardware detection | None (always loads) | `Probe` field matches FRU/GPIO |
| Multi-board support | One config per image | Multiple configs, auto-selected |
| Uses `Class: "temp"/"fan"` | No (uses `type` field) | Yes |

## Testing

### Verify Service Running

```bash
systemctl status phosphor-pid-control
```

### Verify Entity Manager Config Loaded

```bash
# Check Entity Manager has PID entries
busctl tree xyz.openbmc_project.EntityManager | grep -i pid

# Check phosphor-pid-control picked it up
journalctl -u phosphor-pid-control | head -20
```

### Check Zone Status

```bash
# List thermal zones
busctl tree xyz.openbmc_project.State.FanCtrl

# Get zone mode
busctl get-property xyz.openbmc_project.State.FanCtrl \
    /xyz/openbmc_project/control/thermal/0 \
    xyz.openbmc_project.Control.ThermalMode Current
```

### Manual Fan Control

```bash
# Set to manual mode
busctl set-property xyz.openbmc_project.State.FanCtrl \
    /xyz/openbmc_project/control/thermal/0 \
    xyz.openbmc_project.Control.ThermalMode Current s "Manual"

# Set fan speed (0-255)
echo 200 > /sys/class/hwmon/hwmon0/pwm1
```

## PID Tuning Tips

1. **Start conservative**: Use low integral gain (-0.1)
2. **Test at idle**: Verify fans maintain minimum speed
3. **Test under load**: Verify fans increase appropriately
4. **Check failsafe**: Remove a sensor and verify fans go to 100%
5. **Add slew limits**: Prevent rapid speed changes

## Related Documentation

- [Fan Control Guide](../../03-core-services/04-fan-control-guide.md)
- [Entity Manager Guide](../../03-core-services/03-entity-manager-guide.md)
- [phosphor-pid-control](https://github.com/openbmc/phosphor-pid-control)
