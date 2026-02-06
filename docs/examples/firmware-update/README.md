# Firmware Update Examples

Example scripts for firmware update operations.

## Contents

- `firmware-update.sh` - Firmware update helper script
- `version-check.sh` - Check current firmware versions

## Related Guide

[Firmware Update Guide](../../05-advanced/03-firmware-update-guide.md)

## Quick Test

```bash
# Check current firmware version
busctl get-property xyz.openbmc_project.Software.BMC.Updater \
    /xyz/openbmc_project/software/functional \
    xyz.openbmc_project.Software.Version Version

# List all firmware images
busctl tree xyz.openbmc_project.Software.BMC.Updater

# Update via Redfish
curl -k -u root:0penBmc -X POST \
    https://localhost/redfish/v1/UpdateService/Actions/UpdateService.SimpleUpdate \
    -H "Content-Type: application/json" \
    -d '{"ImageURI": "tftp://192.168.1.10/obmc-phosphor-image.static.mtd.tar"}'
```
