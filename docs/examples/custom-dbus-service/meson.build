# Meson build file for example-greeting D-Bus service
#
# This build file demonstrates how to:
#   1. Find sdbusplus and use sdbus++ for YAML -> C++ code generation
#   2. Compile and link a D-Bus service for OpenBMC
#   3. Install the service binary and systemd unit file
#
# Build:
#   meson setup builddir
#   meson compile -C builddir
#
# Install (in Yocto or with --prefix):
#   meson install -C builddir

project(
    'example-greeting',
    'cpp',
    version: '1.0.0',
    default_options: [
        'cpp_std=c++23',
        'warning_level=3',
        'werror=true',
    ],
    meson_version: '>=0.63.0',
)

# =============================================================================
# Dependencies
# =============================================================================

# sdbusplus - D-Bus C++ bindings used by all OpenBMC services
sdbusplus_dep = dependency('sdbusplus')

# Boost - required for sdbusplus::asio integration (io_context, signal_set)
boost_dep = dependency(
    'boost',
    modules: ['coroutine', 'context'],
    required: false,
)
if not boost_dep.found()
    boost_dep = dependency('boost')
endif

# phosphor-logging - standard OpenBMC structured logging (optional, for
# production services you would use lg2::info/error instead of std::cout)
phosphor_logging_dep = dependency('phosphor-logging', required: false)

# systemd - for installing the service unit file
systemd_dep = dependency('systemd', required: false)

# =============================================================================
# sdbus++ Code Generation (YAML -> C++ server bindings)
# =============================================================================
# The sdbusplus package provides the sdbus++ tool and a meson helper module.
# It reads YAML interface definitions and generates:
#   - server.hpp / server.cpp  (server-side bindings)
#   - client.hpp               (client-side bindings)
#   - error.hpp / error.cpp    (error definitions, if any)

sdbusplus_prog = find_program('sdbus++', required: true)
sdbusplus_dep_files = files()

# Define the interface to generate code for.
# The path corresponds to the YAML file location:
#   xyz/openbmc_project/Example/Greeting.interface.yaml
generated_sources = []
generated_headers = []

# Generate server bindings from the YAML interface definition.
# sdbus++ reads xyz/openbmc_project/Example/Greeting.interface.yaml and
# produces C++ headers and sources for the server-side implementation.
greeting_iface = 'xyz/openbmc_project/Example/Greeting'

generated_headers += custom_target(
    'greeting-server-hpp',
    output: 'server.hpp',
    command: [
        sdbusplus_prog,
        '-r', meson.current_source_dir(),
        'interface',
        'server-header',
        greeting_iface,
    ],
    capture: true,
)

generated_sources += custom_target(
    'greeting-server-cpp',
    output: 'server.cpp',
    command: [
        sdbusplus_prog,
        '-r', meson.current_source_dir(),
        'interface',
        'server-cpp',
        greeting_iface,
    ],
    capture: true,
)

# =============================================================================
# Service Executable
# =============================================================================

deps = [sdbusplus_dep, boost_dep]
if phosphor_logging_dep.found()
    deps += phosphor_logging_dep
endif

executable(
    'example-greeting',
    'main.cpp',
    generated_sources,
    generated_headers,
    dependencies: deps,
    install: true,
    install_dir: get_option('bindir'),
)

# =============================================================================
# systemd Service Unit
# =============================================================================
# Install the systemd service file so the service starts automatically on boot.

if systemd_dep.found()
    systemd_system_unit_dir = systemd_dep.get_variable(
        'systemdsystemunitdir',
        pkgconfig_define: ['prefix', get_option('prefix')],
    )
else
    systemd_system_unit_dir = '/lib/systemd/system'
endif

install_data(
    'example-greeting.service',
    install_dir: systemd_system_unit_dir,
)
