# D-Bus Examples

Examples demonstrating D-Bus communication patterns in OpenBMC.

## Examples

| Directory | Description |
|-----------|-------------|
| `client/` | D-Bus client - reading properties, calling methods |
| `server/` | D-Bus server - exposing properties and methods |

## Building with Docker (Recommended)

No SDK or local toolchain needed — just Docker.

```bash
# Build everything
./build.sh

# Run the demo (starts server, calls methods, reads properties)
./run.sh

# Or get an interactive shell to experiment
./run.sh shell
```

The Docker image builds sdbusplus from source and compiles both examples.
A session D-Bus daemon is started inside the container so the examples
run without a real BMC.

### What the demo does

```
=== Starting D-Bus Server ===
=== Introspecting Server ===
=== Calling Increment ===
=== Reading Counter ===
=== Setting Counter to 42 ===
=== Calling Add(8) ===
=== Calling Reset ===
Demo complete!
```

### Interactive shell

```bash
./run.sh shell

# Inside the container:
./builddir/dbus_server &
busctl --system introspect xyz.openbmc_project.Example.Server \
    /xyz/openbmc_project/example/server
busctl --system call xyz.openbmc_project.Example.Server \
    /xyz/openbmc_project/example/server \
    xyz.openbmc_project.Example.Counter Increment
```

## Building with OpenBMC SDK

```bash
# Source the SDK environment
source /opt/openbmc-phosphor/VERSION/environment-setup-*

# Build with meson
meson setup builddir
meson compile -C builddir
```

## Building on Target BMC

Copy the source files to the BMC and compile:

```bash
g++ -std=c++23 dbus_client.cpp -o dbus_client -lsdbusplus
g++ -std=c++23 dbus_server.cpp -o dbus_server -lsdbusplus -lboost_system
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

### Docker build fails at sdbusplus

If sdbusplus build fails, it may be due to API changes upstream. Try pinning
to a known-good commit by editing the `git clone` line in `Dockerfile`:

```dockerfile
RUN git clone --depth 1 --branch v1.0.0 https://github.com/openbmc/sdbusplus ...
```

### "Connection refused" or "No such service"

Ensure you're running on a system with the D-Bus daemon:
- Docker container (via `./run.sh`)
- Real BMC hardware
- QEMU emulator

### "Permission denied"

D-Bus policies may restrict access. On BMC, run as root.
In Docker, the entrypoint uses a session bus so no root is needed.

## Related Documentation

- [D-Bus Guide](../../docs/02-architecture/02-dbus-guide.md)
- [sdbusplus Repository](https://github.com/openbmc/sdbusplus)
- [phosphor-dbus-interfaces](https://github.com/openbmc/phosphor-dbus-interfaces)
