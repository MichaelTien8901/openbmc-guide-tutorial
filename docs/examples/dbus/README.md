# D-Bus Examples

Examples demonstrating D-Bus communication patterns in OpenBMC.

## Examples

| Directory | Description |
|-----------|-------------|
| `client/` | D-Bus client - reading properties, calling methods |
| `server/` | D-Bus server - exposing properties and methods |
| `async/`  | Asynchronous D-Bus patterns with Boost.Asio |

## Building

### With OpenBMC SDK

```bash
# Source the SDK environment
source /opt/openbmc-phosphor/VERSION/environment-setup-*

# Build client
cd client
$CXX -std=c++20 dbus_client.cpp -o dbus_client \
    $(pkg-config --cflags --libs sdbusplus)

# Build server
cd ../server
$CXX -std=c++20 dbus_server.cpp -o dbus_server \
    $(pkg-config --cflags --libs sdbusplus)
```

### On Target BMC

Copy the source files to the BMC and compile:

```bash
# On the BMC
g++ -std=c++20 dbus_client.cpp -o dbus_client -lsdbusplus
g++ -std=c++20 dbus_server.cpp -o dbus_server -lsdbusplus -lboost_system
```

## Running

### Client Example

```bash
# On BMC or QEMU
./dbus_client

# Expected output:
# Connected to D-Bus system bus
# === Reading Host State ===
# Current Host State: xyz.openbmc_project.State.Host.HostState.Off
# ...
```

### Server Example

```bash
# Terminal 1: Start the server
./dbus_server

# Terminal 2: Interact with the server
busctl introspect xyz.openbmc_project.Example.Server \
    /xyz/openbmc_project/example/server

busctl get-property xyz.openbmc_project.Example.Server \
    /xyz/openbmc_project/example/server \
    xyz.openbmc_project.Example.Counter Counter

busctl call xyz.openbmc_project.Example.Server \
    /xyz/openbmc_project/example/server \
    xyz.openbmc_project.Example.Counter Increment

busctl set-property xyz.openbmc_project.Example.Server \
    /xyz/openbmc_project/example/server \
    xyz.openbmc_project.Example.Counter Counter x 100
```

## Key Concepts Demonstrated

### Client (`dbus_client.cpp`)

- Connecting to system bus
- Reading single properties
- Reading all properties (GetAll)
- Using Object Mapper to find objects
- Discovering services for objects
- Error handling

### Server (`dbus_server.cpp`)

- Creating a D-Bus service
- Requesting a well-known name
- Exposing read-write properties with validation
- Exposing read-only properties
- Implementing methods with/without parameters
- Emitting PropertiesChanged signals
- Using Boost.Asio for the event loop

## Dependencies

- sdbusplus
- boost (for server async example)

## Troubleshooting

### "Connection refused" or "No such service"

Ensure you're running on a system with the D-Bus daemon:
- Real BMC hardware
- QEMU emulator
- System with systemd and dbus-daemon

### "Permission denied"

D-Bus policies may restrict access. On BMC, run as root.

### Build errors about missing headers

Ensure the SDK is properly sourced and pkg-config can find sdbusplus:
```bash
pkg-config --cflags --libs sdbusplus
```

## Related Documentation

- [D-Bus Guide](../../docs/02-architecture/02-dbus-guide.md)
- [sdbusplus Repository](https://github.com/openbmc/sdbusplus)
- [phosphor-dbus-interfaces](https://github.com/openbmc/phosphor-dbus-interfaces)
