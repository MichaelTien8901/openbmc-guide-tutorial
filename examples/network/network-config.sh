#!/bin/bash
# Network configuration script for OpenBMC
# Usage: network-config.sh [show|set-static|set-dhcp|set-hostname|set-dns]

SERVICE="xyz.openbmc_project.Network"
ETH_PATH="/xyz/openbmc_project/network/eth0"
ETH_IFACE="xyz.openbmc_project.Network.EthernetInterface"
IP_IFACE="xyz.openbmc_project.Network.IP"
SYS_PATH="/xyz/openbmc_project/network/config"

show_config() {
    echo "=== Network Configuration ==="

    # DHCP status
    DHCP=$(busctl get-property $SERVICE $ETH_PATH $ETH_IFACE DHCPEnabled 2>/dev/null | awk '{print $2}')
    echo "DHCP Enabled: $DHCP"

    # MAC address
    MAC=$(busctl get-property $SERVICE $ETH_PATH $ETH_IFACE MACAddress 2>/dev/null | awk -F'"' '{print $2}')
    echo "MAC Address: $MAC"

    # IP addresses
    echo ""
    echo "IP Addresses:"
    IP_PATHS=$(busctl tree $SERVICE 2>/dev/null | grep "$ETH_PATH/" | grep -v "neighbor")
    for ip_path in $IP_PATHS; do
        ADDR=$(busctl get-property $SERVICE $ip_path $IP_IFACE Address 2>/dev/null | awk -F'"' '{print $2}')
        PREFIX=$(busctl get-property $SERVICE $ip_path $IP_IFACE PrefixLength 2>/dev/null | awk '{print $2}')
        if [ -n "$ADDR" ]; then
            echo "  $ADDR/$PREFIX"
        fi
    done

    # Default gateway
    GATEWAY=$(busctl get-property $SERVICE $SYS_PATH xyz.openbmc_project.Network.SystemConfiguration DefaultGateway 2>/dev/null | awk -F'"' '{print $2}')
    echo ""
    echo "Default Gateway: $GATEWAY"

    # Hostname
    HOSTNAME=$(busctl get-property $SERVICE $SYS_PATH xyz.openbmc_project.Network.SystemConfiguration HostName 2>/dev/null | awk -F'"' '{print $2}')
    echo "Hostname: $HOSTNAME"
}

set_static() {
    IP="$1"
    PREFIX="$2"
    GATEWAY="$3"

    if [ -z "$IP" ] || [ -z "$PREFIX" ] || [ -z "$GATEWAY" ]; then
        echo "Usage: $0 set-static IP PREFIX GATEWAY"
        echo "Example: $0 set-static 192.168.1.100 24 192.168.1.1"
        exit 1
    fi

    # Disable DHCP
    busctl set-property $SERVICE $ETH_PATH $ETH_IFACE DHCPEnabled b false

    # Add static IP
    busctl call $SERVICE $ETH_PATH $ETH_IFACE IP ssys \
        "xyz.openbmc_project.Network.IP.Protocol.IPv4" \
        "$IP" "$PREFIX" "$GATEWAY"

    echo "Static IP configured: $IP/$PREFIX, Gateway: $GATEWAY"
}

set_dhcp() {
    busctl set-property $SERVICE $ETH_PATH $ETH_IFACE DHCPEnabled b true
    echo "DHCP enabled on eth0"
}

set_hostname() {
    HOSTNAME="$1"
    if [ -z "$HOSTNAME" ]; then
        echo "Usage: $0 set-hostname HOSTNAME"
        exit 1
    fi

    busctl set-property $SERVICE $SYS_PATH \
        xyz.openbmc_project.Network.SystemConfiguration HostName s "$HOSTNAME"
    echo "Hostname set to: $HOSTNAME"
}

case "$1" in
    show)
        show_config
        ;;
    set-static)
        set_static "$2" "$3" "$4"
        ;;
    set-dhcp)
        set_dhcp
        ;;
    set-hostname)
        set_hostname "$2"
        ;;
    *)
        echo "Usage: $0 [show|set-static|set-dhcp|set-hostname]"
        echo ""
        echo "Commands:"
        echo "  show                          - Show current network configuration"
        echo "  set-static IP PREFIX GATEWAY  - Set static IP address"
        echo "  set-dhcp                      - Enable DHCP"
        echo "  set-hostname NAME             - Set system hostname"
        exit 1
        ;;
esac
