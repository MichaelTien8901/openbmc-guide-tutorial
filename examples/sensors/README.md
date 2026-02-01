# Sensor Examples

Example code and configurations for OpenBMC sensors.

## Examples

| Directory/File | Description |
|----------------|-------------|
| `virtual-sensor/` | Custom virtual sensor implementation |
| `external-sensor/` | External sensor client example |
| `sensor-reader.cpp` | D-Bus sensor reading utility |

## Virtual Sensor

A virtual sensor calculates values from other sensors. Example: total system power from individual PSU readings.

```bash
cd virtual-sensor
# Build with OpenBMC SDK
$CXX -std=c++20 virtual_sensor.cpp -o virtual_sensor $(pkg-config --cflags --libs sdbusplus)
```

## External Sensor

External sensors allow setting sensor values from external sources (scripts, other daemons).

```bash
cd external-sensor
# Run the example
./set_external_sensor.sh
```

## Sensor Reader

A utility to read and display sensor values:

```bash
# Build
$CXX -std=c++20 sensor_reader.cpp -o sensor_reader $(pkg-config --cflags --libs sdbusplus)

# Run
./sensor_reader temperature
./sensor_reader voltage
./sensor_reader all
```

## Entity Manager Configurations

See `../entity-manager/` for sensor configuration examples.

## Related Documentation

- [D-Bus Sensors Guide](../../docs/03-core-services/01-dbus-sensors-guide.md)
- [Hwmon Sensors Guide](../../docs/03-core-services/02-hwmon-sensors-guide.md)
- [Entity Manager Guide](../../docs/03-core-services/03-entity-manager-guide.md)
