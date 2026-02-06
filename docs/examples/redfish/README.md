# Redfish Custom Resource Examples

Example implementation of custom OEM Redfish resources for OpenBMC bmcweb.

> **Requires OpenBMC bitbake environment** — this example is a header file
> that integrates directly into the bmcweb source tree. It cannot be built
> standalone.

## Files

| File | Description |
|------|-------------|
| `oem_resource.hpp` | Custom OEM resource handler (header-only) |
| `oem-schema.json` | OEM schema definition template |
| `test_oem_resource.sh` | Test script for verifying endpoints |

## What This Adds

Three custom Redfish endpoints:

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/redfish/v1/Oem/MyVendor/` | GET | OEM root with links to sub-resources |
| `/redfish/v1/Oem/MyVendor/BoardInfo` | GET | Board info (type, CPU/DIMM slots, power) |
| `/redfish/v1/Oem/MyVendor/DiagnosticService` | GET | Available diagnostic tests |
| `.../DiagnosticService/Actions/DiagnosticService.RunTest` | POST | Run a diagnostic test |

## Quick Start with BitBake + QEMU

### 1. Patch bmcweb with your OEM resource

Create a bbappend for bmcweb in your OEM layer:

```bash
# In your OpenBMC build tree
mkdir -p meta-myoem/recipes-phosphor/interfaces/bmcweb

# Create the bbappend
cat > meta-myoem/recipes-phosphor/interfaces/bmcweb/bmcweb_%.bbappend << 'EOF'
FILESEXTRAPATHS:prepend := "${THISDIR}/files:"
SRC_URI += "file://0001-Add-MyVendor-OEM-resources.patch"
EOF
```

### 2. Generate the patch

```bash
# Clone bmcweb and create a patch
git clone https://github.com/openbmc/bmcweb
cd bmcweb

# Copy the OEM header
cp /path/to/oem_resource.hpp redfish-core/lib/

# Register the routes — edit redfish-core/lib/oem.hpp (or similar):
#   #include "oem_resource.hpp"
#   // In the setup function:
#   requestRoutesMyVendorOem(app);

# Create the patch
git add -A && git commit -m "Add MyVendor OEM resources"
git format-patch HEAD~1 -o /path/to/meta-myoem/recipes-phosphor/interfaces/bmcweb/files/
```

### 3. Build and boot QEMU

```bash
bitbake obmc-phosphor-image

# Start QEMU
./scripts/run-qemu.sh ast2600-evb
```

### 4. Test from host

```bash
# OEM root
curl -k -u root:0penBmc https://localhost:2443/redfish/v1/Oem/MyVendor/

# Board info
curl -k -u root:0penBmc https://localhost:2443/redfish/v1/Oem/MyVendor/BoardInfo

# Diagnostic service
curl -k -u root:0penBmc https://localhost:2443/redfish/v1/Oem/MyVendor/DiagnosticService

# Run a diagnostic test
curl -k -u root:0penBmc -X POST \
    -H "Content-Type: application/json" \
    -d '{"TestId": 1}' \
    https://localhost:2443/redfish/v1/Oem/MyVendor/DiagnosticService/Actions/DiagnosticService.RunTest

# Or use the test script
./test_oem_resource.sh localhost:2443
```

## Key Patterns Demonstrated

### Route Registration

```cpp
BMCWEB_ROUTE(app, "/redfish/v1/Oem/<str>/BoardInfo")
    .privileges(redfish::privileges::getManager)
    .methods(boost::beast::http::verb::get)(handler);
```

### Async D-Bus Property Read

```cpp
sdbusplus::asio::getProperty<std::string>(
    *crow::connections::systemBus,
    "xyz.openbmc_project.Inventory.Manager",
    "/xyz/openbmc_project/inventory/system/board",
    "xyz.openbmc_project.Inventory.Decorator.Asset",
    "Manufacturer",
    [asyncResp](const boost::system::error_code& ec,
                const std::string& value) { ... });
```

### POST Action with JSON Parsing

```cpp
std::optional<uint32_t> testId;
if (!json_util::readJsonAction(req, asyncResp->res, "TestId", testId))
    return;
```

## Schema Registration

For Redfish compliance, register your OEM schema with DMTF or document it
locally. The `oem-schema.json` provides a starting template.

## Related Documentation

- [Redfish Guide](../../docs/04-interfaces/02-redfish-guide.md)
- [bmcweb Repository](https://github.com/openbmc/bmcweb)
- [DMTF Redfish](https://www.dmtf.org/standards/redfish)
