# Sensor Examples

Example code and configurations for OpenBMC sensors.

## Examples

| Directory/File | Description |
|----------------|-------------|
| `virtual-sensor/` | Custom virtual sensor implementation |
| `external-sensor/` | External sensor client example |
| `sensor-reader.cpp` | D-Bus sensor reading utility |

## Building with Docker (Recommended)

```bash
./build.sh        # build with Docker
./run.sh           # run demo (starts virtual sensor, introspects it)
./run.sh shell     # interactive shell
```

The Docker image builds sdbusplus from source and compiles both
`sensor_reader` and `virtual_sensor`. A session D-Bus is started
inside the container so the examples work without a real BMC.

## Building with OpenBMC SDK

```bash
source /opt/openbmc-phosphor/VERSION/environment-setup-*

meson setup builddir
meson compile -C builddir
```

## External Sensor

External sensors allow setting sensor values from external sources (scripts, other daemons).

```bash
cd external-sensor
./set_external_sensor.sh
```

## Entity Manager Configurations

See `../entity-manager/` for sensor configuration examples.

## Related Documentation

- [D-Bus Sensors Guide](../../03-core-services/01-dbus-sensors-guide.md)
- [Hwmon Sensors Guide](../../03-core-services/02-hwmon-sensors-guide.md)
- [Entity Manager Guide](../../03-core-services/03-entity-manager-guide.md)
