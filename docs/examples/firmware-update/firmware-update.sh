#!/bin/bash
# Firmware update helper script
# Usage: firmware-update.sh [status|upload|activate|delete]

SERVICE="xyz.openbmc_project.Software.BMC.Updater"
BASE_PATH="/xyz/openbmc_project/software"
VERSION_IFACE="xyz.openbmc_project.Software.Version"
ACTIVATION_IFACE="xyz.openbmc_project.Software.Activation"

show_status() {
    echo "=== Firmware Status ==="

    # Current active version
    echo "Active Firmware:"
    FUNCTIONAL=$(busctl get-property $SERVICE $BASE_PATH/functional $VERSION_IFACE Version 2>/dev/null | awk -F'"' '{print $2}')
    echo "  Version: $FUNCTIONAL"

    # List all images
    echo ""
    echo "Available Images:"
    IMAGES=$(busctl tree $SERVICE 2>/dev/null | grep "$BASE_PATH/" | grep -v "functional\|active\|updater")

    for img in $IMAGES; do
        ID=$(basename $img)
        VERSION=$(busctl get-property $SERVICE $img $VERSION_IFACE Version 2>/dev/null | awk -F'"' '{print $2}')
        PURPOSE=$(busctl get-property $SERVICE $img $VERSION_IFACE Purpose 2>/dev/null | awk -F'"' '{print $2}' | awk -F'.' '{print $NF}')
        ACTIVATION=$(busctl get-property $SERVICE $img $ACTIVATION_IFACE Activation 2>/dev/null | awk -F'"' '{print $2}' | awk -F'.' '{print $NF}')

        echo "  [$ID] $VERSION ($PURPOSE) - $ACTIVATION"
    done
}

upload_image() {
    IMAGE_PATH="$1"
    if [ -z "$IMAGE_PATH" ]; then
        echo "Usage: $0 upload IMAGE_PATH"
        echo "Example: $0 upload /tmp/obmc-phosphor-image.static.mtd.tar"
        exit 1
    fi

    if [ ! -f "$IMAGE_PATH" ]; then
        echo "Error: File not found: $IMAGE_PATH"
        exit 1
    fi

    echo "Uploading firmware image..."
    # Copy to /tmp/images for software manager to pick up
    cp "$IMAGE_PATH" /tmp/images/
    echo "Image uploaded. Monitor activation status with: $0 status"
}

activate_image() {
    IMAGE_ID="$1"
    if [ -z "$IMAGE_ID" ]; then
        echo "Usage: $0 activate IMAGE_ID"
        echo "Use '$0 status' to get IMAGE_ID"
        exit 1
    fi

    IMAGE_PATH="$BASE_PATH/$IMAGE_ID"

    # Set RequestedActivation to Active
    busctl set-property $SERVICE $IMAGE_PATH $ACTIVATION_IFACE RequestedActivation s \
        "xyz.openbmc_project.Software.Activation.RequestedActivations.Active"

    echo "Activation requested for $IMAGE_ID"
    echo "Monitor progress with: $0 status"
}

delete_image() {
    IMAGE_ID="$1"
    if [ -z "$IMAGE_ID" ]; then
        echo "Usage: $0 delete IMAGE_ID"
        exit 1
    fi

    IMAGE_PATH="$BASE_PATH/$IMAGE_ID"
    busctl call $SERVICE $IMAGE_PATH xyz.openbmc_project.Object.Delete Delete
    echo "Image $IMAGE_ID deleted"
}

case "$1" in
    status)
        show_status
        ;;
    upload)
        upload_image "$2"
        ;;
    activate)
        activate_image "$2"
        ;;
    delete)
        delete_image "$2"
        ;;
    *)
        echo "Usage: $0 [status|upload|activate|delete]"
        echo ""
        echo "Commands:"
        echo "  status              - Show firmware status and available images"
        echo "  upload IMAGE_PATH   - Upload new firmware image"
        echo "  activate IMAGE_ID   - Activate uploaded image"
        echo "  delete IMAGE_ID     - Delete firmware image"
        exit 1
        ;;
esac
