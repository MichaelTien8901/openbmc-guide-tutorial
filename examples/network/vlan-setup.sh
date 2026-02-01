#!/bin/bash
# VLAN setup script for OpenBMC
# Usage: vlan-setup.sh [create|delete|list] VLAN_ID

SERVICE="xyz.openbmc_project.Network"
ETH_PATH="/xyz/openbmc_project/network/eth0"
VLAN_IFACE="xyz.openbmc_project.Network.VLAN"

case "$1" in
    create)
        if [ -z "$2" ]; then
            echo "Usage: $0 create VLAN_ID"
            echo "Example: $0 create 100"
            exit 1
        fi
        VLAN_ID="$2"

        # Create VLAN interface
        busctl call $SERVICE $ETH_PATH $VLAN_IFACE VLAN q "$VLAN_ID"
        echo "Created VLAN $VLAN_ID on eth0"
        echo "New interface: eth0.$VLAN_ID"
        ;;

    delete)
        if [ -z "$2" ]; then
            echo "Usage: $0 delete VLAN_ID"
            exit 1
        fi
        VLAN_ID="$2"
        VLAN_PATH="/xyz/openbmc_project/network/eth0_$VLAN_ID"

        # Delete VLAN interface
        busctl call $SERVICE $VLAN_PATH xyz.openbmc_project.Object.Delete Delete
        echo "Deleted VLAN $VLAN_ID"
        ;;

    list)
        echo "=== VLAN Interfaces ==="
        busctl tree $SERVICE 2>/dev/null | grep "eth0_" | while read path; do
            VLAN_ID=$(busctl get-property $SERVICE $path $VLAN_IFACE Id 2>/dev/null | awk '{print $2}')
            if [ -n "$VLAN_ID" ]; then
                echo "  eth0.$VLAN_ID (ID: $VLAN_ID)"
            fi
        done
        ;;

    *)
        echo "Usage: $0 [create|delete|list] [VLAN_ID]"
        echo ""
        echo "Commands:"
        echo "  create VLAN_ID  - Create VLAN interface"
        echo "  delete VLAN_ID  - Delete VLAN interface"
        echo "  list            - List all VLAN interfaces"
        exit 1
        ;;
esac
