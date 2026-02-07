# BitBake recipe for the Example Greeting D-Bus Service
#
# This recipe demonstrates the standard pattern for packaging a custom
# D-Bus service in OpenBMC using the obmc-phosphor-dbus-service class.
#
# Usage:
#   1. Place this file in your machine layer:
#      meta-yourmachine/recipes-phosphor/example/example-greeting_git.bb
#   2. Update SRC_URI and SRCREV to point to your source repository
#   3. Add to your image:
#      IMAGE_INSTALL:append = " example-greeting"
#   4. Build:
#      bitbake example-greeting

SUMMARY = "Example Greeting D-Bus Service"
DESCRIPTION = "A tutorial D-Bus service demonstrating sdbusplus properties, \
methods, and signals on OpenBMC. Uses sdbus++ YAML code generation and the \
sdbusplus::asio object server pattern."
HOMEPAGE = "https://github.com/openbmc/openbmc"
LICENSE = "Apache-2.0"
LIC_FILES_CHKSUM = "file://LICENSE;md5=86d3f3a95c324c9479bd8986968f4327"

# ============================================================================
# Build system
# ============================================================================
# inherit meson for the build, pkgconfig for dependency resolution, and
# obmc-phosphor-dbus-service for automatic D-Bus service file installation
# and bus name registration with the OpenBMC infrastructure.
inherit meson pkgconfig obmc-phosphor-dbus-service

# ============================================================================
# Source
# ============================================================================
# Update these for your actual source repository. For local development you
# can use file:// URIs instead.
SRC_URI = "git://github.com/myorg/example-greeting.git;branch=main;protocol=https"
SRCREV = "HEAD"

# For local development, uncomment below and comment out the git SRC_URI:
# SRC_URI = " \
#     file://main.cpp \
#     file://meson.build \
#     file://example-greeting.service \
#     file://xyz/openbmc_project/Example/Greeting.interface.yaml \
# "

S = "${WORKDIR}/git"

# ============================================================================
# Dependencies
# ============================================================================
# Build-time dependencies: libraries and tools needed to compile the service.
# sdbusplus provides both the C++ library and the sdbus++ code generator.
DEPENDS += " \
    sdbusplus \
    sdbusplus-tools-native \
    boost \
    phosphor-logging \
    systemd \
"

# Runtime dependencies: packages that must be present on the target BMC.
RDEPENDS:${PN} += " \
    sdbusplus \
    libsystemd \
"

# ============================================================================
# D-Bus service configuration
# ============================================================================
# The obmc-phosphor-dbus-service class uses these variables to:
#   - Install the systemd .service file
#   - Register the D-Bus bus name with the system
#   - Create D-Bus activation files if needed
#
# DBUS_SERVICE:${PN} lists the D-Bus well-known names this package provides.
# The class will look for a matching .service file to install.
DBUS_SERVICE:${PN} = "xyz.openbmc_project.Example.Greeting"

# SYSTEMD_SERVICE:${PN} specifies the systemd unit file(s) to install.
SYSTEMD_SERVICE:${PN} = "example-greeting.service"

# ============================================================================
# Extra meson options (if needed)
# ============================================================================
# Pass additional meson configuration options here. For example, to disable
# tests in CI builds:
# EXTRA_OEMESON = "-Dtests=disabled"

# ============================================================================
# Package configuration
# ============================================================================
# Ensure the installed binary is included in the package.
FILES:${PN} += " \
    ${bindir}/example-greeting \
    ${systemd_system_unitdir}/example-greeting.service \
"
