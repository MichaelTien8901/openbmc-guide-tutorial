# Redfish Custom Resource Examples

Example implementation of custom OEM Redfish resources for OpenBMC bmcweb.

## Files

| File | Description |
|------|-------------|
| `oem_resource.hpp` | Custom OEM resource handler |
| `meson.build` | Build integration snippet |
| `oem-schema.json` | OEM schema definition |
| `test_oem_resource.sh` | Test script for the OEM resource |

## Overview

This example demonstrates how to add custom OEM Redfish resources to bmcweb. The example adds:

- `/redfish/v1/Oem/MyVendor/` - OEM root
- `/redfish/v1/Oem/MyVendor/BoardInfo` - Custom board info resource
- `/redfish/v1/Oem/MyVendor/DiagnosticService` - Diagnostic actions

## Integration

### Step 1: Add Header File

Copy `oem_resource.hpp` to bmcweb source:

```bash
cp oem_resource.hpp <bmcweb-source>/redfish-core/lib/
```

### Step 2: Register Routes

Edit `<bmcweb-source>/redfish-core/lib/oem.hpp` to include your routes:

```cpp
#include "oem_resource.hpp"

// In the appropriate location:
requestRoutesMyVendorOem(app);
```

### Step 3: Build bmcweb

```bash
meson setup build
meson compile -C build
```

## Testing

### Using curl

```bash
# Get OEM root
curl -k -u root:0penBmc https://localhost/redfish/v1/Oem/MyVendor/

# Get board info
curl -k -u root:0penBmc https://localhost/redfish/v1/Oem/MyVendor/BoardInfo

# Run diagnostic
curl -k -u root:0penBmc -X POST \
    -H "Content-Type: application/json" \
    -d '{"TestId": 1}' \
    https://localhost/redfish/v1/Oem/MyVendor/DiagnosticService/Actions/DiagnosticService.RunTest
```

### Using Test Script

```bash
./test_oem_resource.sh <bmc-ip>
```

## Schema Registration

For proper Redfish compliance, register your OEM schema with DMTF or document it locally. The `oem-schema.json` provides a template.

## Related Documentation

- [Redfish Guide](../../docs/04-interfaces/02-redfish-guide.md)
- [bmcweb Repository](https://github.com/openbmc/bmcweb)
- [DMTF Redfish](https://www.dmtf.org/standards/redfish)
