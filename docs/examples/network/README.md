# Network Examples

Example configurations for phosphor-networkd.

## Contents

- `network-config.sh` - Network configuration script
- `static-ip.json` - Static IP configuration
- `vlan-setup.sh` - VLAN configuration script

## Related Guide

[Network Guide](../../docs/03-core-services/07-network-guide.md)

## Quick Test

```bash
# List network interfaces
busctl tree xyz.openbmc_project.Network

# Get IP address
busctl get-property xyz.openbmc_project.Network \
    /xyz/openbmc_project/network/eth0 \
    xyz.openbmc_project.Network.EthernetInterface DHCPEnabled

# Set static IP via Redfish
curl -k -u root:0penBmc -X PATCH \
    https://localhost/redfish/v1/Managers/bmc/EthernetInterfaces/eth0 \
    -H "Content-Type: application/json" \
    -d '{"IPv4StaticAddresses": [{"Address": "192.168.1.100", "SubnetMask": "255.255.255.0", "Gateway": "192.168.1.1"}]}'
```
