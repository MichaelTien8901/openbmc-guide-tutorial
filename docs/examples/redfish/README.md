# Redfish Custom Resource Examples

Example implementation of custom OEM Redfish resources for OpenBMC bmcweb.

> **Requires OpenBMC bitbake environment** — this example is a header file
> that integrates directly into the bmcweb source tree. It cannot be built
> standalone.

## Files

| File | Description |
|------|-------------|
| `oem_resource.hpp` | Custom OEM resource handler (header-only, integrates into bmcweb) |
| `oem-schema.json` | OEM JSON Schema definition (for documentation and validation tools) |
| `test_oem_resource.sh` | Test script for verifying endpoints from the host |

## What This Adds

Four custom Redfish endpoints under your vendor's OEM namespace:

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/redfish/v1/Oem/MyVendor/` | GET | OEM root with links to sub-resources |
| `/redfish/v1/Oem/MyVendor/BoardInfo` | GET | Board info (type, CPU/DIMM slots, power) |
| `/redfish/v1/Oem/MyVendor/DiagnosticService` | GET | Available diagnostic tests |
| `.../DiagnosticService/Actions/DiagnosticService.RunTest` | POST | Run a diagnostic test |

## How bmcweb Routes Work

Before diving into the steps, it helps to understand bmcweb's architecture:

- **Header-only resources** — each Redfish resource lives in a `.hpp` file under
  `redfish-core/lib/`. There is no separate `.cpp` compilation; bmcweb includes
  headers directly.
- **BMCWEB_ROUTE macro** — registers a URL pattern with an HTTP method and
  privilege check. `<str>` in the path captures a string parameter passed to
  your handler.
- **asyncResp pattern** — handlers receive a `shared_ptr<AsyncResp>`. You
  populate `asyncResp->res.jsonValue` (a `nlohmann::json` object). The response
  is sent automatically when the last reference to `asyncResp` is released,
  which means multiple async D-Bus calls can populate the response in parallel.
- **Route registration** — each `.hpp` file exposes a `requestRoutes*(App& app)`
  function. This function is called once at startup from `src/webserver_main.cpp`
  (or a file included by it) to wire up all URL handlers.
- **No runtime schema validation** — bmcweb does **not** validate its JSON
  responses against schema files. The `@odata.type` field is metadata for
  clients, not enforced by the server.

## Step-by-Step Integration

### Step 1: Create a Yocto Layer for Your OEM Customizations

bmcweb is built by bitbake as part of the OpenBMC image. To modify it, you
create a **bbappend** — a Yocto mechanism that patches an existing recipe
without forking the upstream source.

```bash
# In your OpenBMC build tree, create the layer structure
mkdir -p meta-myoem/recipes-phosphor/interfaces/bmcweb/files
mkdir -p meta-myoem/conf

# Create layer.conf so bitbake recognizes this layer
cat > meta-myoem/conf/layer.conf << 'LAYEREOF'
BBPATH .= ":${LAYERDIR}"
BBFILES += ""
BBFILE_COLLECTIONS += "meta-myoem"
BBFILE_PATTERN_meta-myoem = ""
LAYERSERIES_COMPAT_meta-myoem = "nanbield scarthgap"
LAYEREOF

# Create the bbappend — this tells bitbake to apply your patch on top of
# the upstream bmcweb recipe
cat > meta-myoem/recipes-phosphor/interfaces/bmcweb/bmcweb_%.bbappend << 'EOF'
# FILESEXTRAPATHS:prepend tells bitbake to look in our files/ directory
# for any patches or files referenced by SRC_URI
FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

# SRC_URI += appends our patch to the list of sources
SRC_URI += "file://0001-Add-MyVendor-OEM-resources.patch"
EOF
```

**What this does:**
- `FILESEXTRAPATHS:prepend` — adds your `files/` directory to the search path
  so bitbake can find your patch file
- `bmcweb_%.bbappend` — the `%` wildcard matches any version of the bmcweb
  recipe, so your patch applies regardless of the upstream version string
- The actual code change lives in the `.patch` file (created in Step 2)

### Step 2: Generate the Patch

You need to modify two things in bmcweb: (a) add your OEM header file, and
(b) register its routes so bmcweb calls them at startup.

```bash
# Clone upstream bmcweb
git clone https://github.com/openbmc/bmcweb
cd bmcweb
```

**2a. Copy the OEM header into bmcweb's resource directory:**

```bash
cp /path/to/oem_resource.hpp redfish-core/lib/
```

This places your handler alongside the standard resources like `managers.hpp`,
`systems.hpp`, `chassis.hpp`, etc.

**2b. Register routes in the main application:**

bmcweb registers all Redfish routes during startup. You need to add a call to
your `requestRoutesMyVendorOem(app)` function. The exact file varies by bmcweb
version, but it is typically `src/webserver_main.cpp`:

```cpp
// Near the top, add the include
#include "redfish-core/lib/oem_resource.hpp"

// In the section where other requestRoutes* functions are called, add:
redfish::requestRoutesMyVendorOem(app);
```

This single call registers all four routes (OEM root, BoardInfo,
DiagnosticService, RunTest action) because `requestRoutesMyVendorOem` calls each
sub-function internally.

**2c. Create the git patch:**

```bash
git add -A
git commit -m "Add MyVendor OEM resources"

# Format as a patch file in your bbappend's files/ directory
git format-patch HEAD~1 -o /path/to/meta-myoem/recipes-phosphor/interfaces/bmcweb/files/
```

This produces `0001-Add-MyVendor-OEM-resources.patch` which bitbake will apply
on top of upstream bmcweb before building.

### Step 3: Add the Layer and Build

```bash
# Return to your OpenBMC build directory
cd /path/to/openbmc

# Add your layer to bblayers.conf
bitbake-layers add-layer /path/to/meta-myoem

# Build the full image (includes your patched bmcweb)
bitbake obmc-phosphor-image
```

### Step 4: Boot in QEMU and Test

```bash
# Start QEMU — exposes HTTPS on port 2443
./scripts/run-qemu.sh ast2600-evb

# Wait for boot to complete (login prompt appears), then test from host:

# OEM root — returns links to BoardInfo and DiagnosticService
curl -k -u root:0penBmc https://localhost:2443/redfish/v1/Oem/MyVendor/

# Board info — returns board type, slot counts, power
curl -k -u root:0penBmc https://localhost:2443/redfish/v1/Oem/MyVendor/BoardInfo

# Diagnostic service — lists available tests
curl -k -u root:0penBmc https://localhost:2443/redfish/v1/Oem/MyVendor/DiagnosticService

# Run a diagnostic test — POST with JSON body
curl -k -u root:0penBmc -X POST \
    -H "Content-Type: application/json" \
    -d '{"TestId": 1}' \
    https://localhost:2443/redfish/v1/Oem/MyVendor/DiagnosticService/Actions/DiagnosticService.RunTest

# Or use the test script to run all tests at once
./test_oem_resource.sh localhost:2443
```

## Schema Registration

### What `@odata.type` Means

Every Redfish response includes an `@odata.type` field like
`#OemBoardInfo.v1_0_0.BoardInfo`. This tells clients:

| Part | Example | Meaning |
|------|---------|---------|
| `#` prefix | `#` | Indicates a type reference |
| Schema name | `OemBoardInfo` | Which JSON Schema document defines this type |
| Version | `v1_0_0` | Schema version (major_minor_errata) |
| Type name | `BoardInfo` | The specific type within the schema |

### Does bmcweb Validate Against Schemas?

**No.** bmcweb does not load or validate JSON responses against schema files at
runtime. Your handler directly populates `asyncResp->res.jsonValue` with
whatever JSON you construct. The `@odata.type` value is a string you set — there
is no server-side check that your response actually matches a schema.

This means:
- Your OEM resources **work without any schema file deployed** on the BMC
- The `oem-schema.json` file in this example is for **documentation and external
  validation tools**, not consumed by bmcweb itself
- Clients (like Redfish Service Validator) may use `@odata.type` to look up a
  schema for validation, but the BMC itself does not

### Do You Need to Register Schemas Locally?

**For basic functionality: No.** Your OEM endpoints will serve correct JSON
responses without any schema registration. Most real-world OEM extensions on
OpenBMC simply set `@odata.type` and move on.

**For Redfish compliance testing: It depends.** The DMTF
[Redfish Service Validator](https://github.com/DMTF/Redfish-Service-Validator)
checks responses against schemas. For OEM types, it will look for schemas at:

1. **`/redfish/v1/JsonSchemas/`** — bmcweb serves standard DMTF schemas at this
   endpoint. It does **not** automatically serve OEM schemas. If you want the
   validator to find your schema locally, you would need to add a route that
   serves your OEM schema JSON (more effort than it's usually worth).

2. **The `$id` URL in your schema** — The validator may try to fetch the schema
   from the URL in `"$id": "http://myvendor.com/schemas/v1/..."`. In practice,
   this URL is often unreachable, and the validator gracefully skips OEM types.

3. **Local schema directory** — The validator supports a `--schema_directory`
   flag where you can point it at your OEM schema files.

### Schema Registration Options (from simple to thorough)

| Approach | Effort | When to Use |
|----------|--------|-------------|
| **Do nothing** | None | Development, internal use. OEM endpoints work fine. Validator skips unknown OEM types. |
| **Document in repo** | Low | Provide `oem-schema.json` alongside your code for reference. This is what our example does. |
| **Feed to validator** | Medium | Use `--schema_directory` when running Redfish Service Validator to validate your OEM responses. |
| **Serve via bmcweb** | High | Add a route to serve your schema at `/redfish/v1/JsonSchemas/OemBoardInfo/`. Only needed if clients must discover the schema from the BMC. |
| **Register with DMTF** | Very High | Submit to DMTF for inclusion in the official schema bundle. Only for schemas intended to become industry-standard. |

### Recommended Approach

For most OEM extensions, **keep the schema file in your source repo for
documentation** and use the validator's `--schema_directory` option when you need
compliance testing:

```bash
# Run Redfish Service Validator with your OEM schemas
python3 RedfishServiceValidator.py \
    --ip https://localhost:2443 \
    --auth root:0penBmc \
    --schema_directory /path/to/your/schemas/
```

## Key Patterns Demonstrated

### Route Registration

```cpp
// BMCWEB_ROUTE registers a URL pattern with bmcweb's router
// <str> captures the vendor name as a std::string parameter
BMCWEB_ROUTE(app, "/redfish/v1/Oem/<str>/BoardInfo")
    .privileges(redfish::privileges::getManager)  // Requires ConfigureManager privilege
    .methods(boost::beast::http::verb::get)(handler);
```

### Vendor Name Validation

Every handler checks that the vendor segment matches your name, returning 404
for other vendors:

```cpp
if (vendorName != oemVendorName)
{
    messages::resourceNotFound(asyncResp->res, "BoardInfo", vendorName);
    return;
}
```

### Async D-Bus Property Read

Properties from OpenBMC services are read asynchronously. The response is held
open until all async callbacks complete:

```cpp
sdbusplus::asio::getProperty<std::string>(
    *crow::connections::systemBus,
    "xyz.openbmc_project.Inventory.Manager",        // D-Bus service
    "/xyz/openbmc_project/inventory/system/board",   // Object path
    "xyz.openbmc_project.Inventory.Decorator.Asset", // Interface
    "Manufacturer",                                   // Property name
    [asyncResp](const boost::system::error_code& ec,
                const std::string& value) {
        if (ec)
        {
            asyncResp->res.jsonValue["Manufacturer"] = "Unknown";
            return;
        }
        asyncResp->res.jsonValue["Manufacturer"] = value;
    });
```

### POST Action with JSON Parsing

For write operations, bmcweb provides `readJsonAction` to safely extract fields
from the request body with type checking and error responses:

```cpp
std::optional<uint32_t> testId;
if (!json_util::readJsonAction(req, asyncResp->res, "TestId", testId))
    return;  // readJsonAction already set the error response
```

## Related Documentation

- [Redfish Guide](../../04-interfaces/02-redfish-guide.md) — full bmcweb architecture and patterns
- [bmcweb Repository](https://github.com/openbmc/bmcweb)
- [DMTF Redfish](https://www.dmtf.org/standards/redfish)
- [Redfish Service Validator](https://github.com/DMTF/Redfish-Service-Validator)
