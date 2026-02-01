---
layout: default
title: D-Bus Guide
parent: Architecture
nav_order: 2
difficulty: beginner
prerequisites:
  - openbmc-overview
---

# D-Bus Guide
{: .no_toc }

Master D-Bus communication in OpenBMC.
{: .fs-6 .fw-300 }

## Table of Contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

## Overview

D-Bus is the central communication system in OpenBMC. All services expose their functionality through D-Bus, enabling:

- **Loose coupling**: Services don't need to know about each other's implementation
- **Discovery**: Services can be found dynamically at runtime
- **Introspection**: Interfaces can be explored without documentation
- **Language agnostic**: Any language with D-Bus bindings can participate

---

## D-Bus Concepts

### Core Components

```
┌─────────────────────────────────────────────────────────────────┐
│                         D-Bus Daemon                            │
│                    (Message Router)                             │
└─────────────────────────────────────────────────────────────────┘
         │                    │                    │
         ▼                    ▼                    ▼
┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐
│    Service A    │  │    Service B    │  │    Service C    │
│                 │  │                 │  │                 │
│ Well-known name │  │ Well-known name │  │ Well-known name │
│ xyz.openbmc_    │  │ xyz.openbmc_    │  │ xyz.openbmc_    │
│ project.ServiceA│  │ project.ServiceB│  │ project.ServiceC│
└─────────────────┘  └─────────────────┘  └─────────────────┘
```

### Terminology

| Term | Description | Example |
|------|-------------|---------|
| **Bus** | Communication channel | System bus (shared by all) |
| **Service** | Application connected to bus | `xyz.openbmc_project.State.Host` |
| **Object** | Resource exposed by service | `/xyz/openbmc_project/state/host0` |
| **Interface** | Contract defining methods/properties | `xyz.openbmc_project.State.Host` |
| **Property** | Data exposed by object | `CurrentHostState` |
| **Method** | Action that can be invoked | `Reboot()` |
| **Signal** | Broadcast notification | `PropertiesChanged` |

### Naming Conventions

OpenBMC uses consistent naming:

```
Service:   xyz.openbmc_project.<Category>.<Name>
Object:    /xyz/openbmc_project/<category>/<name>
Interface: xyz.openbmc_project.<Category>.<Name>
```

Examples:
- `xyz.openbmc_project.State.Host` - Host state service
- `/xyz/openbmc_project/state/host0` - Host 0 state object
- `xyz.openbmc_project.Sensor.Value` - Sensor value interface

---

## Using busctl

`busctl` is the primary tool for D-Bus interaction.

### List Services

```bash
# List all services
busctl list

# Filter OpenBMC services
busctl list | grep xyz.openbmc_project
```

### Explore Objects

```bash
# Show object tree for a service
busctl tree xyz.openbmc_project.State.Host

# Example output:
# └─/xyz
#   └─/xyz/openbmc_project
#     └─/xyz/openbmc_project/state
#       └─/xyz/openbmc_project/state/host0
```

### Introspect Objects

```bash
# Show interfaces, methods, properties, signals
busctl introspect xyz.openbmc_project.State.Host \
    /xyz/openbmc_project/state/host0

# Example output:
# NAME                                TYPE      SIGNATURE RESULT/VALUE
# xyz.openbmc_project.State.Host      interface -         -
# .CurrentHostState                   property  s         "xyz.openbmc_project..."
# .RequestedHostTransition            property  s         "xyz.openbmc_project..."
```

### Read Properties

```bash
# Get a single property
busctl get-property xyz.openbmc_project.State.Host \
    /xyz/openbmc_project/state/host0 \
    xyz.openbmc_project.State.Host \
    CurrentHostState

# Output: s "xyz.openbmc_project.State.Host.HostState.Off"
```

### Set Properties

```bash
# Set a property (request host power on)
busctl set-property xyz.openbmc_project.State.Host \
    /xyz/openbmc_project/state/host0 \
    xyz.openbmc_project.State.Host \
    RequestedHostTransition s \
    "xyz.openbmc_project.State.Host.Transition.On"
```

### Call Methods

```bash
# Call a method
busctl call xyz.openbmc_project.ObjectMapper \
    /xyz/openbmc_project/object_mapper \
    xyz.openbmc_project.ObjectMapper \
    GetSubTree sias "/" 0 1 "xyz.openbmc_project.Sensor.Value"
```

### Monitor Signals

```bash
# Watch for property changes
busctl monitor xyz.openbmc_project.State.Host

# Watch all D-Bus traffic (verbose)
dbus-monitor --system
```

---

## phosphor-dbus-interfaces

Interface definitions live in the `phosphor-dbus-interfaces` repository.

### YAML Format

Interfaces are defined in YAML:

```yaml
# xyz/openbmc_project/Example/MyInterface.interface.yaml
description: >
    Example interface demonstrating YAML format.

properties:
    - name: MyProperty
      type: string
      description: An example string property.

    - name: MyValue
      type: int32
      description: An example integer property.

methods:
    - name: DoSomething
      description: Performs an action.
      parameters:
          - name: Input
            type: string
            description: Input parameter.
      returns:
          - name: Result
            type: boolean
            description: Success or failure.

signals:
    - name: SomethingHappened
      description: Emitted when something happens.
      properties:
          - name: What
            type: string
```

### Type Signatures

D-Bus uses type signatures:

| Signature | Type | C++ Type |
|-----------|------|----------|
| `s` | String | `std::string` |
| `b` | Boolean | `bool` |
| `i` | Int32 | `int32_t` |
| `u` | Uint32 | `uint32_t` |
| `x` | Int64 | `int64_t` |
| `t` | Uint64 | `uint64_t` |
| `d` | Double | `double` |
| `o` | Object path | `sdbusplus::message::object_path` |
| `a` | Array | `std::vector<T>` |
| `(...)` | Struct | `std::tuple<...>` |
| `a{sv}` | Dict | `std::map<std::string, std::variant<...>>` |

---

## sdbusplus Library

`sdbusplus` is the C++ library for D-Bus in OpenBMC.

{: .note }
> **Source Reference**: [sdbusplus](https://github.com/openbmc/sdbusplus)
> - Bus API: [include/sdbusplus/bus.hpp](https://github.com/openbmc/sdbusplus/blob/master/include/sdbusplus/bus.hpp)
> - Examples: [example/](https://github.com/openbmc/sdbusplus/tree/master/example)

### Creating a D-Bus Client

```cpp
#include <sdbusplus/bus.hpp>
#include <iostream>

int main()
{
    // Connect to system bus
    auto bus = sdbusplus::bus::new_default();

    // Create method call
    auto method = bus.new_method_call(
        "xyz.openbmc_project.State.Host",           // Service
        "/xyz/openbmc_project/state/host0",         // Object
        "org.freedesktop.DBus.Properties",          // Interface
        "Get"                                        // Method
    );

    // Add arguments
    method.append("xyz.openbmc_project.State.Host", // Interface
                  "CurrentHostState");               // Property

    // Call and get reply
    auto reply = bus.call(method);

    // Extract result
    std::variant<std::string> value;
    reply.read(value);

    std::cout << "Host state: " << std::get<std::string>(value) << "\n";

    return 0;
}
```

### Creating a D-Bus Server

```cpp
#include <sdbusplus/bus.hpp>
#include <sdbusplus/server.hpp>
#include <xyz/openbmc_project/Example/MyInterface/server.hpp>

// Generated server binding
using MyInterfaceInherit = sdbusplus::server::object_t<
    sdbusplus::xyz::openbmc_project::Example::server::MyInterface>;

class MyService : public MyInterfaceInherit
{
  public:
    MyService(sdbusplus::bus_t& bus, const char* path) :
        MyInterfaceInherit(bus, path)
    {
        // Initialize properties
        myProperty("initial value");
    }

    // Property getter/setter are auto-generated

    // Implement methods
    bool doSomething(std::string input) override
    {
        std::cout << "doSomething called with: " << input << "\n";
        return true;
    }
};

int main()
{
    auto bus = sdbusplus::bus::new_default();

    // Request well-known name
    bus.request_name("xyz.openbmc_project.Example");

    // Create server object
    MyService myService(bus, "/xyz/openbmc_project/example");

    // Process D-Bus events
    while (true)
    {
        bus.process_discard();
        bus.wait();
    }

    return 0;
}
```

### Async with sdbusplus and Boost.Asio

```cpp
#include <sdbusplus/asio/connection.hpp>
#include <sdbusplus/asio/object_server.hpp>
#include <boost/asio.hpp>

int main()
{
    boost::asio::io_context io;
    auto conn = std::make_shared<sdbusplus::asio::connection>(io);

    conn->request_name("xyz.openbmc_project.Example");

    sdbusplus::asio::object_server server(conn);

    auto iface = server.add_interface(
        "/xyz/openbmc_project/example",
        "xyz.openbmc_project.Example.MyInterface"
    );

    // Add property
    std::string myValue = "hello";
    iface->register_property("MyProperty", myValue,
        // Setter
        [](const std::string& newValue, std::string& value) {
            value = newValue;
            return true;
        }
    );

    iface->initialize();

    io.run();
    return 0;
}
```

---

## phosphor-objmgr (Object Mapper)

The Object Mapper tracks all D-Bus objects and their interfaces.

### Query Objects by Interface

```bash
# Find all objects implementing Sensor.Value
busctl call xyz.openbmc_project.ObjectMapper \
    /xyz/openbmc_project/object_mapper \
    xyz.openbmc_project.ObjectMapper \
    GetSubTree sias "/" 0 1 "xyz.openbmc_project.Sensor.Value"
```

### Get Service for Object

```bash
# Find which service owns an object
busctl call xyz.openbmc_project.ObjectMapper \
    /xyz/openbmc_project/object_mapper \
    xyz.openbmc_project.ObjectMapper \
    GetObject sas "/xyz/openbmc_project/state/host0" 0
```

### Using mapper CLI

```bash
# List objects with interface
mapper get-subtree / xyz.openbmc_project.Sensor.Value

# Get service for object
mapper get-service /xyz/openbmc_project/state/host0
```

---

## D-Bus Associations

Associations link related objects together.

### Association Structure

```
┌─────────────────────┐           ┌─────────────────────┐
│  /sensors/temp0     │──────────▶│  /inventory/cpu0    │
│                     │  sensors  │                     │
│  associations:      │◀──────────│                     │
│  [inventory,sensors,│  inventory│                     │
│   /inventory/cpu0]  │           │                     │
└─────────────────────┘           └─────────────────────┘
```

### Query Associations

```bash
# Get associations for an object
busctl introspect xyz.openbmc_project.ObjectMapper \
    /xyz/openbmc_project/sensors/temperature/cpu0

# Look for 'associations' property and endpoints
```

---

## Troubleshooting

### Common Issues

**Service not found:**
```bash
# Check if service is running
systemctl status xyz.openbmc_project.ServiceName

# Check service logs
journalctl -u xyz.openbmc_project.ServiceName
```

**Permission denied:**
```bash
# Check D-Bus policy
cat /usr/share/dbus-1/system.d/xyz.openbmc_project.*.conf
```

**Property type mismatch:**
```bash
# Verify property type with introspect
busctl introspect <service> <object> | grep <property>
```

### Debug Commands

```bash
# Verbose D-Bus monitoring
dbus-monitor --system "interface='xyz.openbmc_project.State.Host'"

# Check Object Mapper health
busctl tree xyz.openbmc_project.ObjectMapper

# List all interfaces on an object
busctl introspect <service> <object> | grep interface
```

---

## Next Steps

- **[State Manager Guide]({% link docs/02-architecture/03-state-manager-guide.md %})** - Learn about system state control
- **[D-Bus Sensors Guide]({% link docs/03-core-services/01-dbus-sensors-guide.md %})** - Understand sensor implementation

---

## References

- [phosphor-dbus-interfaces](https://github.com/openbmc/phosphor-dbus-interfaces)
- [sdbusplus](https://github.com/openbmc/sdbusplus)
- [phosphor-objmgr](https://github.com/openbmc/phosphor-objmgr)
- [D-Bus Specification](https://dbus.freedesktop.org/doc/dbus-specification.html)

---

{: .note }
**Tested on**: OpenBMC master, QEMU romulus
