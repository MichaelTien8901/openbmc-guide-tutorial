# Custom D-Bus Service Example

A complete, buildable example of a custom OpenBMC D-Bus service using sdbusplus
with YAML-defined interfaces and sdbus++ code generation.

> **Requires OpenBMC SDK or Yocto build environment** to compile. The YAML
> interface definition is processed by the `sdbus++` tool from sdbusplus to
> generate C++ bindings at build time.

## Files

| File | Description |
|------|-------------|
| `xyz/openbmc_project/Example/Greeting.interface.yaml` | sdbusplus YAML interface definition (property, method, signal) |
| `main.cpp` | Service implementation using `sdbusplus::asio` |
| `meson.build` | Meson build file with sdbus++ code generation |
| `example-greeting.service` | systemd unit file for OpenBMC |
| `example-greeting.bb` | Yocto BitBake recipe using `obmc-phosphor-dbus-service` |

## Interface Summary

**Service name**: `xyz.openbmc_project.Example.Greeting`
**Object path**: `/xyz/openbmc_project/example/greeting`
**Interface**: `xyz.openbmc_project.Example.Greeting`

| Member | Type | Description |
|--------|------|-------------|
| `Name` | property (string, read-write) | Name to greet |
| `Greet` | method (returns string) | Returns a greeting message using the current Name |
| `Greeted` | signal (string) | Emitted each time someone is greeted |

## Building with OpenBMC SDK

```bash
# Source the SDK environment
source /opt/openbmc-phosphor/VERSION/environment-setup-*

# Build
meson setup builddir
meson compile -C builddir
```

The meson build invokes `sdbus++` to generate server bindings from the YAML
interface definition, then compiles and links the service binary.

## Building in Yocto

Place the BitBake recipe in your machine layer:

```
meta-yourmachine/
  recipes-phosphor/
    example/
      example-greeting.bb
```

Then add to your image:

```bitbake
# In local.conf or your image recipe
IMAGE_INSTALL:append = " example-greeting"
```

Build:

```bash
bitbake example-greeting
# or rebuild the full image
bitbake obmc-phosphor-image
```

## Testing on BMC (or QEMU)

```bash
# Check the service is running
systemctl status example-greeting

# Introspect the object
busctl introspect xyz.openbmc_project.Example.Greeting \
    /xyz/openbmc_project/example/greeting

# Read the Name property
busctl get-property xyz.openbmc_project.Example.Greeting \
    /xyz/openbmc_project/example/greeting \
    xyz.openbmc_project.Example.Greeting Name

# Set the Name property
busctl set-property xyz.openbmc_project.Example.Greeting \
    /xyz/openbmc_project/example/greeting \
    xyz.openbmc_project.Example.Greeting Name s "Alice"

# Call the Greet method
busctl call xyz.openbmc_project.Example.Greeting \
    /xyz/openbmc_project/example/greeting \
    xyz.openbmc_project.Example.Greeting Greet

# Monitor for the Greeted signal
busctl monitor xyz.openbmc_project.Example.Greeting &
busctl call xyz.openbmc_project.Example.Greeting \
    /xyz/openbmc_project/example/greeting \
    xyz.openbmc_project.Example.Greeting Greet
```

## How It Works

1. **YAML interface** (`Greeting.interface.yaml`) defines the D-Bus contract:
   a property, a method, and a signal using the sdbusplus schema.

2. **sdbus++ code generation** (invoked by meson) reads the YAML and produces
   C++ header/source files with strongly-typed server bindings.

3. **main.cpp** uses `sdbusplus::asio::connection` and
   `sdbusplus::asio::object_server` to register the generated interface on the
   system bus, implement the method logic, and run the Boost.Asio event loop.

4. **systemd** manages the service lifecycle on the BMC, starting it after
   `dbus.service` is available.

5. **BitBake** builds and installs the service as part of the OpenBMC image,
   inheriting `obmc-phosphor-dbus-service` for proper D-Bus integration.

## Key Concepts Demonstrated

- Writing sdbusplus YAML interface definitions
- Using sdbus++ code generation in a meson build
- Creating an asio-based D-Bus service with properties, methods, and signals
- Packaging a D-Bus service for OpenBMC with systemd and BitBake

## References

- [D-Bus Guide](../../02-architecture/02-dbus-guide.md)
- [sdbusplus Repository](https://github.com/openbmc/sdbusplus)
- [phosphor-dbus-interfaces](https://github.com/openbmc/phosphor-dbus-interfaces)
- [sdbus++ documentation](https://github.com/openbmc/sdbusplus/blob/master/docs/yaml/interface.md)
