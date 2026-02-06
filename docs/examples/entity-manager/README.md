# Entity Manager Configuration Examples

Example JSON configurations for Entity Manager.

## Source Reference

These examples are based on patterns from:
- **Entity Manager repository**: https://github.com/openbmc/entity-manager
- **Configuration examples**: https://github.com/openbmc/entity-manager/tree/master/configurations
- **Schema documentation**: https://github.com/openbmc/entity-manager/blob/master/docs/schema.md

## Files

| File | Description |
|------|-------------|
| `baseboard.json` | Complete board configuration with sensors, fans, FRU |
| `temperature-sensors.json` | I2C temperature sensor examples |
| `adc-sensors.json` | ADC voltage sensor examples |
| `fans.json` | Fan tachometer and PWM configuration |
| `psu.json` | PMBus power supply configuration |
| `fru-eeprom.json` | FRU EEPROM configuration |

## Installation

Copy configurations to the BMC:

```bash
# Copy all configurations
scp *.json root@bmc:/usr/share/entity-manager/configurations/

# Restart Entity Manager
ssh root@bmc systemctl restart xyz.openbmc_project.EntityManager
```

## Testing

### Verify Configuration Loaded

```bash
# Check Entity Manager logs
journalctl -u xyz.openbmc_project.EntityManager -f

# List configured entities
busctl tree xyz.openbmc_project.EntityManager
```

### Verify Sensors

```bash
# List all sensors
busctl tree xyz.openbmc_project.HwmonTempSensor
busctl tree xyz.openbmc_project.ADCSensor
busctl tree xyz.openbmc_project.FanSensor

# Read a sensor value
busctl get-property xyz.openbmc_project.HwmonTempSensor \
    /xyz/openbmc_project/sensors/temperature/Inlet_Temp \
    xyz.openbmc_project.Sensor.Value Value
```

## Customization

1. Modify `Name` fields to match your hardware
2. Update `Bus` and `Address` for your I2C topology
3. Adjust `Thresholds` based on your thermal specifications
4. Update `Probe` conditions to match your FRU data

## Probe Conditions

### Using FRU Probes

If your board has a FRU EEPROM, update the probe:

```json
"Probe": "xyz.openbmc_project.FruDevice({'PRODUCT_PRODUCT_NAME': 'YourBoardName'})"
```

### Using I2C Probes

For boards without FRU:

```json
"Probe": "i2c({'bus': 1, 'address': 72})"
```

### Always Load (Development)

For testing, use:

```json
"Probe": "TRUE"
```

## Related Documentation

- [Entity Manager Guide](../../03-core-services/03-entity-manager-guide.md)
- [D-Bus Sensors Guide](../../03-core-services/01-dbus-sensors-guide.md)
- [Hwmon Sensors Guide](../../03-core-services/02-hwmon-sensors-guide.md)
