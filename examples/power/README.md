# Power Management Examples

Example configurations for power management in OpenBMC.

## Files

| File | Description |
|------|-------------|
| `power-config.json` | GPIO-based power control configuration |
| `regulators-config.json` | Voltage regulator configuration |
| `psu-entity-manager.json` | PSU Entity Manager configuration |
| `power-sequencer.service` | Example systemd power sequencer service |

## Power Configuration

### GPIO Power Control

The `power-config.json` defines GPIO pins for power control:

```bash
# Copy to BMC
scp power-config.json root@bmc:/usr/share/phosphor-state-manager/

# Restart state manager
ssh root@bmc systemctl restart xyz.openbmc_project.State.Chassis
```

### Voltage Regulators

The `regulators-config.json` configures voltage levels:

```bash
# Copy to BMC
scp regulators-config.json root@bmc:/usr/share/phosphor-regulators/config.json

# Restart regulators service
ssh root@bmc systemctl restart phosphor-regulators
```

## Testing

### Check Power State

```bash
obmcutil state
```

### Power On

```bash
obmcutil poweron
```

### Power Off

```bash
obmcutil poweroff
```

### Check PSU Status

```bash
busctl tree xyz.openbmc_project.PSUSensor
```

## Related Documentation

- [Power Management Guide](../../docs/03-core-services/05-power-management-guide.md)
- [State Manager Guide](../../docs/02-architecture/03-state-manager-guide.md)
