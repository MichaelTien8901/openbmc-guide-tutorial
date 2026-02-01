# BitBake recipe for My OEM IPMI Commands
#
# To use this recipe:
# 1. Create a layer for your OEM customizations
# 2. Place this file in recipes-phosphor/ipmi/myoem-ipmi_git.bb
# 3. Update SRC_URI and SRCREV for your repository
# 4. Add to IMAGE_INSTALL in your machine config

SUMMARY = "My OEM IPMI Commands"
DESCRIPTION = "OEM-specific IPMI command handlers for OpenBMC"
HOMEPAGE = "https://github.com/myorg/myoem-ipmi"
LICENSE = "Apache-2.0"
LIC_FILES_CHKSUM = "file://LICENSE;md5=86d3f3a95c324c9479bd8986968f4327"

# Use Meson build system
inherit meson pkgconfig

# Dependencies
DEPENDS += " \
    sdbusplus \
    phosphor-logging \
    phosphor-ipmi-host \
"

# Source configuration - update for your repository
SRC_URI = "git://github.com/myorg/myoem-ipmi.git;branch=main;protocol=https"
SRCREV = "HEAD"

# For local development, you can use:
# SRC_URI = "file://oem_handler.cpp \
#            file://oem_handler.hpp \
#            file://meson.build \
#           "

S = "${WORKDIR}/git"

# Register as an IPMI provider
HOSTIPMI_PROVIDER_LIBRARY += "libmyoemhandler.so"

# Package configuration
FILES:${PN} += "${libdir}/ipmid-providers"

# Runtime dependency
RDEPENDS:${PN} += "phosphor-ipmi-host"
