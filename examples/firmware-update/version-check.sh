#!/bin/bash
# Check firmware versions on OpenBMC

echo "=== BMC Firmware Versions ==="

# BMC Version
BMC_VERSION=$(busctl get-property xyz.openbmc_project.Software.BMC.Updater \
    /xyz/openbmc_project/software/functional \
    xyz.openbmc_project.Software.Version Version 2>/dev/null | awk -F'"' '{print $2}')
echo "BMC Version: ${BMC_VERSION:-Unknown}"

# Build date (from /etc/os-release)
if [ -f /etc/os-release ]; then
    BUILD_ID=$(grep "BUILD_ID" /etc/os-release | cut -d'=' -f2 | tr -d '"')
    echo "Build ID: ${BUILD_ID:-Unknown}"
fi

# Machine info
if [ -f /etc/machine.conf ]; then
    MACHINE=$(grep "MACHINE" /etc/machine.conf | cut -d'=' -f2)
    echo "Machine: ${MACHINE:-Unknown}"
fi

echo ""
echo "=== Host Firmware ==="

# BIOS Version (if available)
BIOS_VERSION=$(busctl get-property xyz.openbmc_project.Software.Host.Updater \
    /xyz/openbmc_project/software/bios_active \
    xyz.openbmc_project.Software.Version Version 2>/dev/null | awk -F'"' '{print $2}')
echo "BIOS Version: ${BIOS_VERSION:-Not available}"

echo ""
echo "=== All Software Inventory ==="
busctl tree xyz.openbmc_project.Software.BMC.Updater 2>/dev/null | grep "/xyz/openbmc_project/software/" | while read path; do
    ID=$(basename $path)
    [ "$ID" = "functional" ] && continue
    [ "$ID" = "active" ] && continue

    VERSION=$(busctl get-property xyz.openbmc_project.Software.BMC.Updater $path \
        xyz.openbmc_project.Software.Version Version 2>/dev/null | awk -F'"' '{print $2}')

    if [ -n "$VERSION" ]; then
        echo "  $ID: $VERSION"
    fi
done
