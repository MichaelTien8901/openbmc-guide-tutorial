# Logging Examples

Example configurations and scripts for phosphor-logging.

## Contents

- `create-event.sh` - Create SEL/Event log entries
- `query-logs.sh` - Query and filter log entries
- `logging-config.json` - Logging configuration example
- `custom-error.yaml` - Custom error definition

## Related Guide

[Logging Guide](../../05-advanced/06-logging-guide.md)

## Quick Test

```bash
# List all log entries
busctl call xyz.openbmc_project.Logging \
    /xyz/openbmc_project/logging \
    org.freedesktop.DBus.ObjectManager GetManagedObjects

# Create an informational log entry
busctl call xyz.openbmc_project.Logging /xyz/openbmc_project/logging \
    xyz.openbmc_project.Logging.Create Create "ssa{ss}" \
    "xyz.openbmc_project.Common.Error.InternalFailure" \
    "xyz.openbmc_project.Logging.Entry.Level.Informational" \
    1 "REASON" "Test log entry"
```
