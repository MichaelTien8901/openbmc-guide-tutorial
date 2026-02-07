---
layout: default
title: Custom D-Bus Services Guide
parent: Architecture
nav_order: 4
difficulty: intermediate
prerequisites:
  - dbus-guide
  - environment-setup
last_modified_date: 2026-02-06
---

# Custom D-Bus Services Guide
{: .no_toc }

Build production-ready D-Bus services for OpenBMC using sdbusplus YAML interfaces, sdbus++ code generation, and proper Yocto integration.
{: .fs-6 .fw-300 }

## Table of Contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

## Overview

Every feature in OpenBMC exposes its data and actions through D-Bus interfaces. When you add new hardware support, implement a custom management feature, or integrate a vendor-specific capability, you create a D-Bus service that other components (Redfish, IPMI, web UI) consume automatically.

This guide walks you through the complete lifecycle of building a custom D-Bus service: defining the interface in YAML, generating C++ bindings with sdbus++, implementing the service logic, and packaging it for the OpenBMC build system. You follow along with a concrete example -- a "Hello World" service that exposes a greeting property and a SayHello method.

By the end of this guide, you have a fully functional D-Bus service running in QEMU that you can introspect with busctl and extend for your own use case.

**Key concepts covered:**
- YAML interface definitions for sdbusplus (properties, methods, signals, enumerations)
- sdbus++ code generation and meson integration
- Async service implementation with sdbusplus::asio
- systemd unit files with D-Bus activation
- Yocto .bb recipes using obmc-phosphor-dbus-service.bbclass

---

## Architecture

A custom D-Bus service in OpenBMC consists of several interconnected pieces. The YAML interface definition serves as the contract, sdbus++ generates the C++ bindings, your implementation provides the business logic, and systemd manages the service lifecycle.

### Component Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                   Custom D-Bus Service Lifecycle                 │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│   ┌──────────────┐    sdbus++     ┌──────────────────────┐      │
│   │  YAML         │──────────────▶│  Generated C++        │      │
│   │  Interface    │   codegen     │  Server Bindings     │      │
│   │  Definition   │               │  (headers + sources) │      │
│   └──────────────┘               └──────────┬───────────┘      │
│                                              │                   │
│                                              ▼                   │
│   ┌──────────────┐               ┌──────────────────────┐      │
│   │  systemd      │    starts     │  Service             │      │
│   │  Unit File   │──────────────▶│  Implementation      │      │
│   └──────────────┘               │  (your C++ code)     │      │
│                                  └──────────┬───────────┘      │
│                                              │                   │
│                                              ▼                   │
│                                  ┌──────────────────────┐      │
│                                  │  D-Bus System Bus    │      │
│                                  └──────────┬───────────┘      │
│                                              │                   │
│                            ┌─────────────────┼──────────────┐   │
│                            ▼                 ▼              ▼   │
│                     ┌──────────┐      ┌──────────┐   ┌────────┐│
│                     │  bmcweb  │      │  ipmid   │   │ busctl ││
│                     │ (Redfish)│      │ (IPMI)   │   │ (CLI)  ││
│                     └──────────┘      └──────────┘   └────────┘│
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### D-Bus Interfaces

| Interface | Object Path | Description |
|-----------|-------------|-------------|
| `xyz.openbmc_project.Example.Greeter` | `/xyz/openbmc_project/example/greeter` | Example greeter service |

### Key Dependencies

- **sdbusplus**: C++ D-Bus library and sdbus++ code generator
- **phosphor-dbus-interfaces**: Standard OpenBMC interface definitions (reference patterns)
- **boost**: Provides Boost.Asio for the async event loop
- **systemd**: Service management and D-Bus activation
- **meson**: Build system with sdbus++ integration

---

## YAML Interface Definition

The sdbusplus YAML format defines D-Bus interfaces declaratively. Each YAML file maps to one D-Bus interface and describes its properties, methods, signals, and enumerations.

### File Organization

Interface YAML files follow a directory structure that mirrors the D-Bus interface name. For an interface named `xyz.openbmc_project.Example.Greeter`, you place the file at:

```
yaml/xyz/openbmc_project/Example/Greeter.interface.yaml
```

Enumeration types go in separate files:

```
yaml/xyz/openbmc_project/Example/Greeter/Status.interface.yaml
```

{: .note }
> The `phosphor-dbus-interfaces` repository at [github.com/openbmc/phosphor-dbus-interfaces](https://github.com/openbmc/phosphor-dbus-interfaces) contains all standard OpenBMC interface definitions. Study its structure when designing your own interfaces.

### Complete YAML Example

Create the interface definition file for the Greeter service:

```yaml
# yaml/xyz/openbmc_project/Example/Greeter.interface.yaml
description: >
    Interface for a greeting service that demonstrates custom D-Bus
    service development in OpenBMC.

properties:
    - name: Greeting
      type: string
      default: "Hello, OpenBMC!"
      description: >
          The current greeting message. Clients can read and modify
          this property.

    - name: GreetCount
      type: uint32
      default: 0
      flags:
          - readonly
      description: >
          Number of times the SayHello method has been called.
          This property is read-only and increments automatically.

    - name: Status
      type: enum[self.Status]
      default: "Ready"
      flags:
          - readonly
      description: >
          Current status of the greeter service.

methods:
    - name: SayHello
      description: >
          Generate a personalized greeting using the current Greeting
          template and the provided name.
      parameters:
          - name: Name
            type: string
            description: The name to greet.
      returns:
          - name: Response
            type: string
            description: The formatted greeting message.
      errors:
          - xyz.openbmc_project.Common.Error.InvalidArgument

    - name: Reset
      description: >
          Reset the GreetCount to zero and restore the default greeting.

signals:
    - name: GreetingChanged
      description: >
          Emitted when the greeting message changes.
      properties:
          - name: OldGreeting
            type: string
            description: The previous greeting message.
          - name: NewGreeting
            type: string
            description: The new greeting message.

enumerations:
    - name: Status
      description: >
          Possible states of the greeter service.
      values:
          - name: Ready
            description: Service is ready to accept requests.
          - name: Busy
            description: Service is processing a request.
          - name: Error
            description: Service encountered an error.
```

### YAML Type Mappings

The YAML `type` field maps to D-Bus type signatures and C++ types:

| YAML Type | D-Bus Signature | C++ Type |
|-----------|-----------------|----------|
| `boolean` | `b` | `bool` |
| `byte` | `y` | `uint8_t` |
| `int16` | `n` | `int16_t` |
| `uint16` | `q` | `uint16_t` |
| `int32` | `i` | `int32_t` |
| `uint32` | `u` | `uint32_t` |
| `int64` | `x` | `int64_t` |
| `uint64` | `t` | `uint64_t` |
| `double` | `d` | `double` |
| `string` | `s` | `std::string` |
| `object_path` | `o` | `sdbusplus::message::object_path` |
| `array[T]` | `aT` | `std::vector<T>` |
| `dict[K, V]` | `a{KV}` | `std::map<K, V>` |
| `enum[self.Name]` | `s` | Generated enum class |

### Property Flags

Use the `flags` field to control property behavior:

| Flag | Effect |
|------|--------|
| `readonly` | Property can only be set by the service implementation, not by D-Bus clients |
| `const` | Property value is set at construction and never changes |

{: .tip }
> Design your interfaces before writing code. A well-designed YAML interface acts as an API contract that other teams can review and depend on.

---

## sdbus++ Code Generation

The `sdbus++` tool reads your YAML interface definitions and generates C++ server bindings. These generated files include abstract base classes with virtual methods for your service implementation to override.

### What sdbus++ Generates

For the `xyz.openbmc_project.Example.Greeter` interface, sdbus++ produces:

| Generated File | Purpose |
|----------------|---------|
| `xyz/openbmc_project/Example/Greeter/server.hpp` | Server-side abstract base class |
| `xyz/openbmc_project/Example/Greeter/server.cpp` | Server-side vtable registration |
| `xyz/openbmc_project/Example/Greeter/client.hpp` | Client-side proxy class |
| `xyz/openbmc_project/Example/Greeter/common.hpp` | Shared type definitions |
| `xyz/openbmc_project/Example/Greeter/error.hpp` | Error type definitions |

### Running sdbus++ Manually

You can run sdbus++ directly to inspect the generated output:

```bash
# Generate server header
sdbus++ -r yaml -t interface server-header \
    xyz.openbmc_project.Example.Greeter > server.hpp

# Generate server implementation
sdbus++ -r yaml -t interface server-cpp \
    xyz.openbmc_project.Example.Greeter > server.cpp

# Generate common types (enums, errors)
sdbus++ -r yaml -t interface common-header \
    xyz.openbmc_project.Example.Greeter > common.hpp
```

{: .note }
> In practice, you rarely run sdbus++ manually. The meson build system handles code generation automatically. The commands above are useful for debugging or understanding the generated code.

### Meson Integration for Code Generation

The sdbusplus project provides meson helper functions that automate code generation. Add this to your `meson.build`:

```meson
sdbusplus_dep = dependency('sdbusplus')
sdbusplus_prog = find_program('sdbus++')

# Define the interface to generate
generated_sources = []
generated_headers = []

# Use sdbusplus meson module for code generation
sdbusplus_project = subproject('sdbusplus', required: true)
sdbusplus_generate = sdbusplus_project.get_variable('sdbusplus_generate')

# Generate server bindings from YAML
generated = sdbusplus_generate.process(
    'yaml/xyz/openbmc_project/Example/Greeter.interface.yaml',
    install_header: false,
)

generated_sources += generated[0]  # .cpp files
generated_headers += generated[1]  # .hpp files
```

For projects that prefer a simpler approach without the meson subproject, you can use custom_target:

```meson
sdbusplus_prog = find_program('sdbus++')

greeter_server_hpp = custom_target(
    'greeter-server-hpp',
    input: [],
    output: 'server.hpp',
    command: [
        sdbusplus_prog, '-r', meson.project_source_root() / 'yaml',
        '-t', 'interface', 'server-header',
        'xyz.openbmc_project.Example.Greeter',
    ],
    capture: true,
)

greeter_server_cpp = custom_target(
    'greeter-server-cpp',
    input: [],
    output: 'server.cpp',
    command: [
        sdbusplus_prog, '-r', meson.project_source_root() / 'yaml',
        '-t', 'interface', 'server-cpp',
        'xyz.openbmc_project.Example.Greeter',
    ],
    capture: true,
)
```

---

## Service Implementation

With the YAML interface defined and code generation configured, you now implement the service itself. OpenBMC services use the sdbusplus::asio integration with Boost.Asio for async event handling.

### Approach 1: Using Generated Server Bindings (Recommended)

This approach inherits from the sdbus++-generated server base class. The generated class provides property storage, vtable registration, and signal emission. You override virtual methods to implement business logic.

```cpp
// greeter_service.hpp
#pragma once

#include <xyz/openbmc_project/Example/Greeter/server.hpp>
#include <sdbusplus/bus.hpp>
#include <sdbusplus/server.hpp>

namespace greeter
{

// Create a convenient type alias for the generated server binding
using GreeterInherit = sdbusplus::server::object_t<
    sdbusplus::xyz::openbmc_project::Example::server::Greeter>;

class GreeterService : public GreeterInherit
{
  public:
    GreeterService(sdbusplus::bus_t& bus, const char* path) :
        GreeterInherit(bus, path)
    {
        // Set initial property values
        greeting("Hello, OpenBMC!");
        greetCount(0);
        status(Status::Ready);
    }

    // Implement the SayHello method (generated as pure virtual)
    std::string sayHello(std::string name) override
    {
        if (name.empty())
        {
            throw sdbusplus::xyz::openbmc_project::Common::Error::
                InvalidArgument();
        }

        // Update the greet count
        greetCount(greetCount() + 1);

        // Build the response using the current greeting
        std::string response = greeting() + " " + name + "!";

        return response;
    }

    // Implement the Reset method
    void reset() override
    {
        std::string oldGreeting = greeting();

        // Restore defaults
        greeting("Hello, OpenBMC!");
        greetCount(0);

        // Emit the GreetingChanged signal
        greeterChanged(oldGreeting, greeting());
    }
};

} // namespace greeter
```

The main function creates the bus connection and instantiates the service:

```cpp
// main.cpp
#include "greeter_service.hpp"

#include <sdbusplus/bus.hpp>
#include <sdbusplus/server/manager.hpp>

#include <iostream>

int main()
{
    constexpr auto serviceName = "xyz.openbmc_project.Example.Greeter";
    constexpr auto objectPath = "/xyz/openbmc_project/example/greeter";

    // Connect to the system bus
    auto bus = sdbusplus::bus::new_default();

    // Create an ObjectManager for introspection support
    sdbusplus::server::manager_t objManager(bus, objectPath);

    // Request the well-known service name
    bus.request_name(serviceName);

    // Create the greeter service object
    greeter::GreeterService greeterObj(bus, objectPath);

    std::cout << "Greeter service running at " << objectPath << "\n";

    // Enter the event loop
    while (true)
    {
        bus.process_discard();
        bus.wait();
    }

    return 0;
}
```

### Approach 2: Using sdbusplus::asio (Async Event Loop)

Many OpenBMC services use the Boost.Asio integration for timers, file descriptor monitoring, and concurrent I/O. This approach registers properties and methods programmatically instead of inheriting from generated bindings.

```cpp
// main_async.cpp
#include <sdbusplus/asio/connection.hpp>
#include <sdbusplus/asio/object_server.hpp>
#include <boost/asio.hpp>

#include <iostream>
#include <string>

int main()
{
    constexpr auto serviceName = "xyz.openbmc_project.Example.Greeter";
    constexpr auto objectPath = "/xyz/openbmc_project/example/greeter";
    constexpr auto interfaceName = "xyz.openbmc_project.Example.Greeter";

    // Create the Boost.Asio IO context
    boost::asio::io_context io;

    // Connect to the system D-Bus
    auto conn = std::make_shared<sdbusplus::asio::connection>(io);
    conn->request_name(serviceName);

    // Create the object server
    sdbusplus::asio::object_server server(conn);

    // Add the interface to the object path
    auto iface = server.add_interface(objectPath, interfaceName);

    // ── Properties ──────────────────────────────────────────────

    std::string greeting = "Hello, OpenBMC!";
    uint32_t greetCount = 0;
    std::string status = "xyz.openbmc_project.Example.Greeter.Status.Ready";

    // Read-write property: Greeting
    iface->register_property(
        "Greeting", greeting,
        // Setter with validation
        [&greeting](const std::string& newValue, std::string& value) {
            if (newValue.empty())
            {
                std::cerr << "Rejected empty greeting\n";
                return false;
            }
            std::cout << "Greeting changed: " << value
                      << " -> " << newValue << "\n";
            value = newValue;
            greeting = newValue;
            return true;
        },
        // Getter
        [&greeting](const std::string& /*value*/) {
            return greeting;
        }
    );

    // Read-only property: GreetCount
    iface->register_property_r(
        "GreetCount", greetCount,
        sdbusplus::vtable::property_::emits_change,
        [&greetCount](const uint32_t&) {
            return greetCount;
        }
    );

    // Read-only property: Status
    iface->register_property_r(
        "Status", status,
        sdbusplus::vtable::property_::emits_change,
        [&status](const std::string&) {
            return status;
        }
    );

    // ── Methods ─────────────────────────────────────────────────

    // Method: SayHello(string Name) -> string Response
    iface->register_method(
        "SayHello",
        [&greeting, &greetCount, &iface](std::string name) {
            if (name.empty())
            {
                throw std::invalid_argument("Name must not be empty");
            }

            greetCount++;
            iface->signal_property("GreetCount");

            std::string response = greeting + " " + name + "!";
            std::cout << "SayHello(\"" << name << "\") -> \""
                      << response << "\" (count: "
                      << greetCount << ")\n";
            return response;
        }
    );

    // Method: Reset()
    iface->register_method(
        "Reset",
        [&greeting, &greetCount, &iface]() {
            greeting = "Hello, OpenBMC!";
            greetCount = 0;
            iface->signal_property("Greeting");
            iface->signal_property("GreetCount");
            std::cout << "Service reset to defaults\n";
        }
    );

    // Initialize the interface (make it visible on D-Bus)
    iface->initialize();

    std::cout << "Greeter service running at " << objectPath << "\n";

    // ── Optional: periodic timer example ────────────────────────

    boost::asio::steady_timer timer(io);
    std::function<void(const boost::system::error_code&)> timerHandler;
    timerHandler = [&timer, &greetCount, &iface,
                    &timerHandler](const boost::system::error_code& ec) {
        if (ec)
        {
            return;
        }
        std::cout << "Heartbeat: greetCount=" << greetCount << "\n";
        timer.expires_after(std::chrono::seconds(60));
        timer.async_wait(timerHandler);
    };
    timer.expires_after(std::chrono::seconds(60));
    timer.async_wait(timerHandler);

    // Run the event loop (blocks until io.stop() is called)
    io.run();

    return 0;
}
```

{: .tip }
> Use Approach 1 (generated bindings) when you want strict interface enforcement -- the compiler verifies that you implement every method. Use Approach 2 (sdbusplus::asio) when you need Boost.Asio features like timers, socket monitoring, or concurrent I/O operations.

### Property Getters and Setters

Properties in sdbusplus support validation and change notification:

```cpp
// Read-write property with validation
iface->register_property(
    "PropertyName", initialValue,
    // Setter: return true to accept, false to reject
    [](const std::string& newValue, std::string& storedValue) {
        if (newValue.length() > 256)
        {
            return false;  // Reject values that are too long
        }
        storedValue = newValue;
        return true;
    }
);

// Read-only property (updates via signal_property)
iface->register_property_r(
    "ReadOnlyProp", value,
    sdbusplus::vtable::property_::emits_change,
    [&value](const auto&) { return value; }
);
```

### Method Handlers

Methods can accept parameters, return values, and throw errors:

```cpp
// Method with parameters and return value
iface->register_method("MethodName",
    [](std::string param1, int32_t param2) -> std::string {
        // Process the request
        return "result";
    }
);

// Method with no parameters or return value
iface->register_method("SimpleMethod", []() {
    // Perform action
});

// Method that throws a D-Bus error
iface->register_method("ValidatedMethod",
    [](std::string input) {
        if (input.empty())
        {
            throw sdbusplus::exception::SdBusError(
                -EINVAL, "xyz.openbmc_project.Common.Error.InvalidArgument");
        }
    }
);
```

---

## Build Configuration (meson.build)

The meson.build file ties together code generation, compilation, and installation. Below is a complete build file for the greeter service.

### Complete meson.build

```meson
project(
    'phosphor-greeter',
    'cpp',
    version: '1.0.0',
    meson_version: '>=0.63.0',
    default_options: [
        'cpp_std=c++23',
        'warning_level=3',
        'werror=true',
        'buildtype=debugoptimized',
    ],
)

# ── Dependencies ─────────────────────────────────────────────────

sdbusplus_dep = dependency('sdbusplus')
boost_dep = dependency(
    'boost',
    modules: ['coroutine', 'context'],
    required: false,
)
systemd_dep = dependency('systemd')
phosphor_logging_dep = dependency('phosphor-logging', required: false)

# ── sdbus++ code generation ──────────────────────────────────────

sdbusplus_prog = find_program('sdbus++', required: true)
sdbusplus_gen_meson_prog = find_program('sdbus++-gen-meson', required: true)

# Generate server bindings from YAML interface definitions.
# The YAML files are under yaml/ in the source tree.
greeter_server_hpp = custom_target(
    'greeter-server-hpp',
    output: 'server.hpp',
    command: [
        sdbusplus_prog,
        '-r', meson.project_source_root() / 'yaml',
        '-t', 'interface',
        'server-header',
        'xyz.openbmc_project.Example.Greeter',
    ],
    capture: true,
)

greeter_server_cpp = custom_target(
    'greeter-server-cpp',
    output: 'server.cpp',
    command: [
        sdbusplus_prog,
        '-r', meson.project_source_root() / 'yaml',
        '-t', 'interface',
        'server-cpp',
        'xyz.openbmc_project.Example.Greeter',
    ],
    capture: true,
)

greeter_common_hpp = custom_target(
    'greeter-common-hpp',
    output: 'common.hpp',
    command: [
        sdbusplus_prog,
        '-r', meson.project_source_root() / 'yaml',
        '-t', 'interface',
        'common-header',
        'xyz.openbmc_project.Example.Greeter',
    ],
    capture: true,
)

generated_sources = [greeter_server_cpp, greeter_server_hpp,
                     greeter_common_hpp]

# ── Service executable ───────────────────────────────────────────

executable(
    'phosphor-greeter',
    'src/main.cpp',
    'src/greeter_service.cpp',
    generated_sources,
    dependencies: [
        sdbusplus_dep,
        phosphor_logging_dep,
    ],
    include_directories: include_directories('src'),
    install: true,
    install_dir: get_option('bindir'),
)

# ── systemd unit installation ────────────────────────────────────

systemd_system_unit_dir = systemd_dep.get_variable(
    'systemdsystemunitdir',
    pkgconfig_define: ['prefix', get_option('prefix')],
)

configure_file(
    input: 'service_files/xyz.openbmc_project.Example.Greeter.service',
    output: 'xyz.openbmc_project.Example.Greeter.service',
    copy: true,
    install_dir: systemd_system_unit_dir,
)

# ── D-Bus service activation file ────────────────────────────────

dbus_system_services_dir = dependency('dbus-1').get_variable(
    'system_bus_services_dir',
    pkgconfig_define: ['prefix', get_option('prefix')],
)

configure_file(
    input: 'service_files/xyz.openbmc_project.Example.Greeter.dbus.service',
    output: 'xyz.openbmc_project.Example.Greeter.service',
    copy: true,
    install_dir: dbus_system_services_dir,
)
```

{: .warning }
> Use `cpp_std=c++23` (or at least `c++20`) for OpenBMC services. The sdbusplus library and OpenBMC coding standards require modern C++ features like `std::expected`, structured bindings, and concepts.

---

## systemd Service File

systemd manages the lifecycle of your D-Bus service. You need two files: a systemd unit file and a D-Bus activation file.

### systemd Unit File

Create `service_files/xyz.openbmc_project.Example.Greeter.service`:

```ini
[Unit]
Description=OpenBMC Example Greeter D-Bus Service
After=dbus.service
After=phosphor-dbus-interfaces-mapper.service
Wants=phosphor-dbus-interfaces-mapper.service

# Start after the BMC is ready
After=mapper-wait@-xyz-openbmc_project-example.service
Wants=mapper-wait@-xyz-openbmc_project-example.service

# Integrate into OpenBMC boot ordering
After=obmc-standby.target
Before=obmc-host-start-pre@0.target

[Service]
Type=dbus
BusName=xyz.openbmc_project.Example.Greeter
ExecStart=/usr/bin/phosphor-greeter
SyslogIdentifier=phosphor-greeter
Restart=on-failure
RestartSec=5

# Security hardening
ProtectSystem=full
ProtectHome=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
```

### D-Bus Activation File

Create `service_files/xyz.openbmc_project.Example.Greeter.dbus.service`:

```ini
[D-BUS Service]
Name=xyz.openbmc_project.Example.Greeter
Exec=/usr/bin/phosphor-greeter
User=root
SystemdService=xyz.openbmc_project.Example.Greeter.service
```

### OpenBMC Target Ordering

OpenBMC defines a target hierarchy that controls the boot sequence. Place your service in the correct position based on when it needs to run:

| Target | When It Runs | Use When |
|--------|-------------|----------|
| `obmc-standby.target` | BMC is ready, before host power-on | Service needed at BMC idle |
| `obmc-host-startmin@.target` | Minimum services for host start | Service required for host boot |
| `obmc-host-start-pre@.target` | Before host power-on GPIO | Pre-power-on initialization |
| `obmc-host-started@.target` | After host is running | Post-boot monitoring |
| `obmc-host-stop-pre@.target` | Before host power-off | Graceful shutdown tasks |

{: .note }
> The `Type=dbus` setting tells systemd to consider the service started once it has acquired its D-Bus bus name. This ensures dependent services do not start until the interface is ready.

---

## Yocto BitBake Recipe

Package your service for the OpenBMC build system with a BitBake recipe. The `obmc-phosphor-dbus-service` bbclass simplifies service packaging.

### Complete .bb Recipe

Create `meta-phosphor/recipes-phosphor/example/phosphor-greeter_1.0.bb`:

```bitbake
SUMMARY = "OpenBMC Example Greeter D-Bus Service"
DESCRIPTION = "Demonstrates how to build a custom D-Bus service for OpenBMC"
HOMEPAGE = "https://github.com/openbmc/openbmc"
LICENSE = "Apache-2.0"
LIC_FILES_CHKSUM = "file://LICENSE;md5=86d3f3a95c324c9479bd8986968f4327"
PR = "r1"

inherit meson
inherit pkgconfig
inherit obmc-phosphor-dbus-service

# Source repository (adjust for your project)
SRC_URI = "git://github.com/openbmc/phosphor-greeter;branch=master;protocol=https"
SRCREV = "${AUTOREV}"

S = "${WORKDIR}/git"

# Build dependencies (compile-time)
DEPENDS += " \
    sdbusplus \
    phosphor-logging \
    boost \
    systemd \
    "

# Runtime dependencies
RDEPENDS:${PN} += " \
    sdbusplus \
    phosphor-logging \
    libsystemd \
    "

# D-Bus service configuration for obmc-phosphor-dbus-service.bbclass
# This bbclass automatically installs the D-Bus activation file and
# links the systemd unit to the appropriate target.
DBUS_SERVICE:${PN} = "xyz.openbmc_project.Example.Greeter.service"

# systemd service configuration
SYSTEMD_SERVICE:${PN} = "xyz.openbmc_project.Example.Greeter.service"
```

### Adding the Recipe to Your Image

Add the package to your machine image configuration:

```bitbake
# In your machine.conf or local.conf
IMAGE_INSTALL:append = " phosphor-greeter"
```

Or add it to a packagegroup:

```bitbake
# In meta-your-machine/recipes-phosphor/packagegroups/packagegroup-your-machine-apps.bb
RDEPENDS:${PN}:append = " phosphor-greeter"
```

### Using bbappend for Customization

To customize the service for your platform without modifying the upstream recipe:

```bitbake
# meta-your-machine/recipes-phosphor/example/phosphor-greeter_%.bbappend

FILESEXTRAPATHS:prepend := "${THISDIR}/${PN}:"

# Override the greeting default
SRC_URI += "file://0001-change-default-greeting.patch"

# Add platform-specific configuration
SRC_URI += "file://greeter-config.json"

do_install:append() {
    install -d ${D}${datadir}/phosphor-greeter
    install -m 0644 ${WORKDIR}/greeter-config.json \
        ${D}${datadir}/phosphor-greeter/
}
```

{: .tip }
> The `obmc-phosphor-dbus-service.bbclass` handles D-Bus activation file installation and systemd service linking automatically. You only need to set `DBUS_SERVICE` and `SYSTEMD_SERVICE` variables.

---

## Verification and Testing

### Build and Deploy

Build the service within the OpenBMC build environment:

```bash
# Build only the greeter package
bitbake phosphor-greeter

# Build the full image with the greeter included
bitbake obmc-phosphor-image
```

### Test in QEMU

Launch the QEMU emulator and verify the service:

```bash
# Start QEMU (ast2600-evb)
./scripts/run-qemu.sh ast2600-evb

# SSH into the BMC
ssh -p 2222 root@localhost
# Password: 0penBmc
```

Once logged in, verify the service:

```bash
# Check service status
systemctl status xyz.openbmc_project.Example.Greeter

# View the object tree
busctl tree xyz.openbmc_project.Example.Greeter

# Introspect the interface
busctl introspect xyz.openbmc_project.Example.Greeter \
    /xyz/openbmc_project/example/greeter

# Read properties
busctl get-property xyz.openbmc_project.Example.Greeter \
    /xyz/openbmc_project/example/greeter \
    xyz.openbmc_project.Example.Greeter \
    Greeting

# Call the SayHello method
busctl call xyz.openbmc_project.Example.Greeter \
    /xyz/openbmc_project/example/greeter \
    xyz.openbmc_project.Example.Greeter \
    SayHello s "World"

# Expected output: s "Hello, OpenBMC! World!"

# Read the updated GreetCount
busctl get-property xyz.openbmc_project.Example.Greeter \
    /xyz/openbmc_project/example/greeter \
    xyz.openbmc_project.Example.Greeter \
    GreetCount

# Expected output: u 1

# Set the Greeting property
busctl set-property xyz.openbmc_project.Example.Greeter \
    /xyz/openbmc_project/example/greeter \
    xyz.openbmc_project.Example.Greeter \
    Greeting s "Greetings from"

# Call SayHello again with the new greeting
busctl call xyz.openbmc_project.Example.Greeter \
    /xyz/openbmc_project/example/greeter \
    xyz.openbmc_project.Example.Greeter \
    SayHello s "OpenBMC Developer"

# Expected output: s "Greetings from OpenBMC Developer!"

# Reset the service
busctl call xyz.openbmc_project.Example.Greeter \
    /xyz/openbmc_project/example/greeter \
    xyz.openbmc_project.Example.Greeter \
    Reset

# Monitor property changes in real time
busctl monitor xyz.openbmc_project.Example.Greeter
```

### Quick Test with Docker

You can also test the async implementation locally using the D-Bus example Docker environment:

```bash
cd docs/examples/dbus
./run.sh shell

# Inside the container, compile and run
g++ -std=c++23 -o greeter main_async.cpp \
    $(pkg-config --cflags --libs sdbusplus) -lboost_system
./greeter &

# Test with busctl
busctl --system call xyz.openbmc_project.Example.Greeter \
    /xyz/openbmc_project/example/greeter \
    xyz.openbmc_project.Example.Greeter \
    SayHello s "Docker"
```

See the complete example at [examples/custom-dbus-service/]({{ site.baseurl }}/examples/custom-dbus-service/).

---

## Troubleshooting

### Issue: Service Fails to Start with "Name already taken"

**Symptom**: journalctl shows `Failed to request name xyz.openbmc_project.Example.Greeter: Name already taken`

**Cause**: Another process already owns the D-Bus bus name. This happens when a previous instance did not shut down cleanly or you have a duplicate service.

**Solution**:
1. Check for running instances: `systemctl status xyz.openbmc_project.Example.Greeter`
2. Stop the existing service: `systemctl stop xyz.openbmc_project.Example.Greeter`
3. Verify no orphan process: `ps aux | grep phosphor-greeter`
4. Kill orphan processes if found: `kill <pid>`

### Issue: sdbus++ Fails with "Interface not found"

**Symptom**: `sdbus++: error: Could not find interface xyz.openbmc_project.Example.Greeter`

**Cause**: The YAML file path does not match the interface name, or the `-r` (root) argument points to the wrong directory.

**Solution**:
1. Verify the YAML file is at `yaml/xyz/openbmc_project/Example/Greeter.interface.yaml`
2. Verify directory structure matches the interface name exactly (case-sensitive)
3. Ensure the `-r` flag points to the parent of the `xyz/` directory

### Issue: Properties Not Visible After Service Starts

**Symptom**: `busctl introspect` shows the interface but no properties or methods.

**Cause**: You forgot to call `iface->initialize()` after registering all properties and methods.

**Solution**: Add `iface->initialize()` after the last `register_property` or `register_method` call. The interface is not published to D-Bus until you call initialize.

### Issue: "Permission denied" When Connecting to System Bus

**Symptom**: Service crashes with `Failed to open system bus: Permission denied`

**Cause**: D-Bus security policy does not allow your service to own the requested bus name.

**Solution**: Create a D-Bus policy file at `/etc/dbus-1/system.d/`:

```xml
<!-- /etc/dbus-1/system.d/xyz.openbmc_project.Example.Greeter.conf -->
<!DOCTYPE busconfig PUBLIC
 "-//freedesktop//DTD D-BUS Bus Configuration 1.0//EN"
 "http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">
<busconfig>
    <policy user="root">
        <allow own="xyz.openbmc_project.Example.Greeter"/>
        <allow send_destination="xyz.openbmc_project.Example.Greeter"/>
    </policy>
    <policy context="default">
        <allow send_destination="xyz.openbmc_project.Example.Greeter"/>
    </policy>
</busconfig>
```

### Issue: BitBake Recipe Build Fails

**Symptom**: `bitbake phosphor-greeter` fails with missing dependency errors.

**Cause**: DEPENDS or RDEPENDS are incomplete, or sdbusplus is not available in the build environment.

**Solution**:
1. Verify `meta-phosphor` layer is included in `bblayers.conf`
2. Check that `sdbusplus-native` is available for code generation: `bitbake sdbusplus-native`
3. Add missing dependencies to DEPENDS in the recipe
4. Run `bitbake -e phosphor-greeter | grep ^DEPENDS` to inspect resolved dependencies

### Debug Commands

```bash
# Check service status
systemctl status xyz.openbmc_project.Example.Greeter

# View service logs
journalctl -u xyz.openbmc_project.Example.Greeter -f

# List all D-Bus services
busctl list | grep Example

# Full introspection of the service
busctl introspect xyz.openbmc_project.Example.Greeter \
    /xyz/openbmc_project/example/greeter

# Monitor all signals from the service
busctl monitor xyz.openbmc_project.Example.Greeter

# Check if D-Bus activation file is installed
ls -la /usr/share/dbus-1/system-services/ | grep Greeter

# Verify systemd unit is installed
systemctl cat xyz.openbmc_project.Example.Greeter
```

---

## References

### Official Resources
- [sdbusplus Repository](https://github.com/openbmc/sdbusplus) -- C++ D-Bus library and sdbus++ code generator
- [phosphor-dbus-interfaces](https://github.com/openbmc/phosphor-dbus-interfaces) -- Standard OpenBMC interface YAML definitions
- [sdbusplus Examples](https://github.com/openbmc/sdbusplus/tree/master/example) -- Official sdbusplus usage examples
- [OpenBMC D-Bus Interface Guidelines](https://github.com/openbmc/docs/blob/master/architecture/interface-overview.md)

### Related Guides
- [D-Bus Fundamentals]({% link docs/02-architecture/02-dbus-guide.md %}) -- Core D-Bus concepts and busctl usage
- [State Manager Guide]({% link docs/02-architecture/03-state-manager-guide.md %}) -- Real-world example of a D-Bus service

### External Documentation
- [D-Bus Specification](https://dbus.freedesktop.org/doc/dbus-specification.html)
- [Meson Build System](https://mesonbuild.com/Reference-manual.html)
- [systemd Service Files](https://www.freedesktop.org/software/systemd/man/systemd.service.html)
- [Yocto Project Reference Manual](https://docs.yoctoproject.org/ref-manual/index.html)

---

{: .note }
**Tested on**: QEMU ast2600-evb, OpenBMC commit `HEAD` (master branch)
Last updated: 2026-02-06
