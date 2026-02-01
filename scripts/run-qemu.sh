#!/bin/bash
# Run OpenBMC in QEMU
# Usage: ./run-qemu.sh [machine] [image-path]

set -e

# Defaults
MACHINE="${1:-romulus}"
IMAGE_PATH="${2:-}"

# Find image if not specified
if [ -z "$IMAGE_PATH" ]; then
    # Try common locations
    SEARCH_PATHS=(
        "build/tmp/deploy/images/${MACHINE}/obmc-phosphor-image-${MACHINE}.static.mtd"
        "../openbmc/build/tmp/deploy/images/${MACHINE}/obmc-phosphor-image-${MACHINE}.static.mtd"
        "tmp/deploy/images/${MACHINE}/obmc-phosphor-image-${MACHINE}.static.mtd"
    )

    for path in "${SEARCH_PATHS[@]}"; do
        if [ -f "$path" ]; then
            IMAGE_PATH="$path"
            break
        fi
    done
fi

if [ -z "$IMAGE_PATH" ] || [ ! -f "$IMAGE_PATH" ]; then
    echo "Error: Could not find OpenBMC image"
    echo ""
    echo "Usage: $0 [machine] [image-path]"
    echo ""
    echo "Example:"
    echo "  $0 romulus"
    echo "  $0 romulus /path/to/obmc-phosphor-image-romulus.static.mtd"
    echo ""
    echo "Build an image first with:"
    echo "  . setup ${MACHINE}"
    echo "  bitbake obmc-phosphor-image"
    exit 1
fi

echo "=========================================="
echo "Starting OpenBMC QEMU"
echo "=========================================="
echo "Machine: ${MACHINE}"
echo "Image: ${IMAGE_PATH}"
echo ""
echo "Network ports:"
echo "  SSH:     localhost:2222"
echo "  HTTPS:   localhost:2443"
echo "  IPMI:    localhost:2623 (UDP)"
echo ""
echo "Login credentials: root / 0penBmc (or no password)"
echo ""
echo "Press Ctrl+A, X to exit QEMU"
echo "=========================================="
echo ""

# Run QEMU
qemu-system-arm \
    -m 256 \
    -M "${MACHINE}-bmc" \
    -nographic \
    -drive "file=${IMAGE_PATH},format=raw,if=mtd" \
    -net nic \
    -net user,hostfwd=tcp::2222-:22,hostfwd=tcp::2443-:443,hostfwd=udp::2623-:623
