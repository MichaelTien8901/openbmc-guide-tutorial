# Fan Control Configuration Examples

Example configurations for phosphor-pid-control (swampd).

## Files

| File | Description |
|------|-------------|
| `zone-config.json` | Basic single-zone PID configuration |
| `multi-zone-config.json` | Multi-zone configuration example |
| `stepwise-config.json` | Table-based stepwise control |
| `entity-manager-fan.json` | Entity Manager integration |

## Installation

### Direct Installation

```bash
# Copy to swampd config directory
scp zone-config.json root@bmc:/usr/share/swampd/config.json

# Restart fan control service
ssh root@bmc systemctl restart phosphor-pid-control
```

### Entity Manager Integration

```bash
# Copy Entity Manager configuration
scp entity-manager-fan.json root@bmc:/usr/share/entity-manager/configurations/

# Restart Entity Manager (will trigger swampd reload)
ssh root@bmc systemctl restart xyz.openbmc_project.EntityManager
```

## Testing

### Verify Service Running

```bash
systemctl status phosphor-pid-control
```

### Monitor Fan Control

```bash
# Watch fan control decisions
journalctl -u phosphor-pid-control -f
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

- [Fan Control Guide](../../docs/03-core-services/04-fan-control-guide.md)
- [phosphor-pid-control](https://github.com/openbmc/phosphor-pid-control)
