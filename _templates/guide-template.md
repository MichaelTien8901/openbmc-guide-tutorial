---
layout: default
title: <GUIDE_TITLE>
parent: <SECTION_NAME>
nav_order: <NAV_ORDER>
difficulty: beginner|intermediate|advanced
prerequisites:
  - <prerequisite-1>
  - <prerequisite-2>
last_modified_date: <DATE>
---

# <GUIDE_TITLE>
{: .no_toc }

<Brief one-line description of what this guide covers>
{: .fs-6 .fw-300 }

## Table of Contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

## Overview

<2-3 paragraphs explaining:>
- What this component/feature does
- Why it matters for BMC development
- When you would use it

**Key concepts covered:**
- Concept 1
- Concept 2
- Concept 3

---

## Architecture

<Explain the component architecture>

### Component Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                      <COMPONENT NAME>                        │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│   ┌──────────┐     ┌──────────┐     ┌──────────┐           │
│   │ Module A │────▶│ Module B │────▶│ Module C │           │
│   └──────────┘     └──────────┘     └──────────┘           │
│                                                              │
└─────────────────────────────────────────────────────────────┘
                           │
                           ▼
                    ┌──────────────┐
                    │    D-Bus     │
                    └──────────────┘
```

### D-Bus Interfaces

| Interface | Object Path | Description |
|-----------|-------------|-------------|
| `xyz.openbmc_project.<Interface>` | `/xyz/openbmc_project/<path>` | <Description> |

### Key Dependencies

- **<Dependency 1>**: <Why it's needed>
- **<Dependency 2>**: <Why it's needed>

---

## Configuration

### Required Files

| File | Location | Purpose |
|------|----------|---------|
| `<filename>` | `<path>` | <Purpose> |

### Configuration Options

#### Option 1: <Option Name>

```json
{
  "option": "value",
  "example": "configuration"
}
```

#### Option 2: <Option Name>

```yaml
option: value
example: configuration
```

### Build-time Options

| Option | Default | Description |
|--------|---------|-------------|
| `<OPTION_NAME>` | `<default>` | <Description> |

Enable in your machine configuration:
```bitbake
# In your machine.conf or local.conf
<OPTION_NAME> = "<value>"
```

---

## Porting Guide

Follow these steps to enable <FEATURE> on your platform:

### Step 1: Prerequisites

Ensure you have:
- [ ] <Prerequisite 1>
- [ ] <Prerequisite 2>

### Step 2: Create Configuration Files

Create `<filename>` at `<path>`:

```json
{
  "your": "configuration"
}
```

### Step 3: Update Recipes

Add to your machine layer:

```bitbake
# meta-<your-machine>/recipes-phosphor/<category>/<recipe>.bbappend

FILESEXTRAPATHS:prepend := "${THISDIR}/${PN}:"

SRC_URI += "file://<your-config-file>"

do_install:append() {
    install -d ${D}${datadir}/<component>
    install -m 0644 ${WORKDIR}/<your-config-file> ${D}${datadir}/<component>/
}
```

### Step 4: Verify

1. Build and flash the image
2. Check the service is running:
   ```bash
   systemctl status <service-name>
   ```
3. Verify via D-Bus:
   ```bash
   busctl tree xyz.openbmc_project.<Service>
   ```

---

## Code Examples

### Example 1: <Example Name>

```cpp
// Brief description of what this example demonstrates
#include <example.hpp>

int main() {
    // Example code
    return 0;
}
```

See the complete example at [examples/<category>/<example>/]({{ site.baseurl }}/examples/<category>/<example>/).

### Example 2: <Example Name>

<Description and code>

---

## Troubleshooting

### Issue: <Common Issue 1>

**Symptom**: <What the user observes>

**Cause**: <Why this happens>

**Solution**:
1. Step 1
2. Step 2
3. Step 3

### Issue: <Common Issue 2>

**Symptom**: <What the user observes>

**Cause**: <Why this happens>

**Solution**: <How to fix it>

### Debug Commands

```bash
# Check service status
systemctl status <service-name>

# View logs
journalctl -u <service-name> -f

# Query D-Bus objects
busctl introspect xyz.openbmc_project.<Service> /xyz/openbmc_project/<path>
```

---

## References

### Official Resources
- [<Component> Repository](https://github.com/openbmc/<repo>)
- [D-Bus Interface Definitions](https://github.com/openbmc/phosphor-dbus-interfaces/tree/master/yaml/xyz/openbmc_project/<interface>)
- [OpenBMC Documentation](https://github.com/openbmc/docs)

### Related Guides
- [<Related Guide 1>]({% link docs/<section>/<guide>.md %})
- [<Related Guide 2>]({% link docs/<section>/<guide>.md %})

### External Documentation
- [<External Resource>](<url>)

---

{: .note }
**Tested on**: QEMU romulus, OpenBMC commit `<commit-hash>`
Last updated: <DATE>
