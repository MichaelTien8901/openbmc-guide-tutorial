# Redfish OEM Extension Examples

Template files for adding custom OEM Redfish resources to OpenBMC bmcweb.
These examples provide a starting point with TODO markers for vendor-specific
customization.

> **Requires OpenBMC bitbake environment** -- the C++ route handler integrates
> directly into the bmcweb source tree and cannot be built standalone. The CSDL
> schema is consumed by Redfish validation tools, not by bmcweb itself.

## Files

| File | Description |
|------|-------------|
| `oem-route-template.cpp` | Skeleton bmcweb OEM route handler with TODO markers for customization |
| `oem-schema.csdl.xml` | Sample CSDL XML schema defining an OEM resource type |
| `test-oem-endpoint.sh` | curl-based script to verify OEM Redfish endpoints |

## What This Provides

A minimal OEM extension with two endpoints:

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/redfish/v1/Oem/<Vendor>/` | GET | OEM root with links to sub-resources |
| `/redfish/v1/Oem/<Vendor>/Health` | GET | Custom health summary resource |

The template is intentionally minimal. The existing `redfish/` example directory
contains a more complete implementation with BoardInfo, DiagnosticService, and
POST action patterns.

## How to Use These Templates

### Step 1: Customize the Route Handler

Open `oem-route-template.cpp` and search for `TODO` comments. At minimum you
need to:

1. Replace `YourVendor` with your vendor name
2. Define the JSON properties your resource exposes
3. Wire up D-Bus calls to read real hardware data

### Step 2: Create a Yocto Patch

```bash
# Clone upstream bmcweb
git clone https://github.com/openbmc/bmcweb
cd bmcweb

# Copy the template (rename as needed)
cp oem-route-template.cpp redfish-core/lib/oem_yourvendor.hpp

# Register routes in src/webserver_main.cpp:
#   #include "redfish-core/lib/oem_yourvendor.hpp"
#   redfish::requestRoutesYourVendorOem(app);

# Commit and format as patch
git add -A
git commit -m "Add YourVendor OEM resources"
git format-patch HEAD~1 -o /path/to/meta-yourvendor/recipes-phosphor/interfaces/bmcweb/files/
```

### Step 3: Create bbappend

```bash
mkdir -p meta-yourvendor/recipes-phosphor/interfaces/bmcweb/files

cat > meta-yourvendor/recipes-phosphor/interfaces/bmcweb/bmcweb_%.bbappend << 'EOF'
FILESEXTRAPATHS:prepend := "${THISDIR}/files:"
SRC_URI += "file://0001-Add-YourVendor-OEM-resources.patch"
EOF
```

### Step 4: Build and Test

```bash
bitbake-layers add-layer /path/to/meta-yourvendor
bitbake obmc-phosphor-image

# Boot in QEMU and test
./scripts/run-qemu.sh ast2600-evb
./test-oem-endpoint.sh localhost:2443
```

## CSDL vs JSON Schema

Redfish defines two schema formats:

| Format | File | Used By |
|--------|------|---------|
| **CSDL (XML)** | `oem-schema.csdl.xml` | DMTF Redfish Service Validator, metadata endpoint (`$metadata`) |
| **JSON Schema** | `oem-schema.json` (see `../redfish/`) | JSON Schema validators, OpenAPI tools |

CSDL is the canonical schema language for OData-based protocols like Redfish.
The `oem-schema.csdl.xml` in this directory demonstrates the CSDL format. For
the JSON Schema equivalent, see `../redfish/oem-schema.json`.

bmcweb does not validate responses against either schema format at runtime. These
files are for documentation, compliance testing, and client tooling.

## Schema Validation

```bash
# Run Redfish Service Validator with your CSDL schema
python3 RedfishServiceValidator.py \
    --ip https://localhost:2443 \
    --auth root:0penBmc \
    --schema_directory /path/to/your/schemas/
```

## Related Examples

- [`../redfish/`](../redfish/) -- Complete OEM resource implementation (BoardInfo, DiagnosticService, Actions)
- [`../ipmi/`](../ipmi/) -- OEM IPMI handler (for comparison with Redfish approach)

## References

- [Redfish Guide](../../04-interfaces/02-redfish-guide.md) -- full bmcweb architecture and patterns
- [bmcweb Repository](https://github.com/openbmc/bmcweb)
- [DMTF Redfish](https://www.dmtf.org/standards/redfish)
- [DMTF CSDL Schema Format](https://www.dmtf.org/dsp/DSP0266) -- OData CSDL specification
- [Redfish Service Validator](https://github.com/DMTF/Redfish-Service-Validator)
