# Robot Framework Test Examples

Example Robot Framework tests for OpenBMC integration testing.

## Files

| File | Description |
|------|-------------|
| `hello_openbmc.robot` | Basic smoke tests - Redfish service root verification |
| `redfish_sensors.robot` | Sensor reading tests via Redfish API |
| `ssh_commands.robot` | SSH-based BMC command execution tests |

## Prerequisites

```bash
# Install Robot Framework
pip3 install robotframework

# Install required libraries
pip3 install robotframework-requests
pip3 install robotframework-sshlibrary
```

## Running Tests Against QEMU

Start QEMU with OpenBMC:

```bash
qemu-system-arm -m 1G -M ast2600-evb -nographic \
    -drive file=obmc-phosphor-image.static.mtd,format=raw,if=mtd \
    -net nic \
    -net user,hostfwd=tcp::2222-:22,hostfwd=tcp::2443-:443
```

Run tests:

```bash
# Run all tests
robot -v OPENBMC_HOST:localhost -v SSH_PORT:2222 -v HTTPS_PORT:2443 .

# Run specific test file
robot -v OPENBMC_HOST:localhost hello_openbmc.robot

# Run tests with specific tag
robot --include smoke .

# Run with verbose output
robot -L DEBUG hello_openbmc.robot
```

## Running Tests Against Real Hardware

```bash
robot -v OPENBMC_HOST:192.168.1.100 \
      -v SSH_PORT:22 \
      -v HTTPS_PORT:443 \
      -v OPENBMC_USERNAME:root \
      -v OPENBMC_PASSWORD:yourpassword \
      .
```

## Test Output

Robot Framework generates:
- `output.xml` - Machine-readable results
- `log.html` - Detailed execution log
- `report.html` - Summary report

View the report:
```bash
xdg-open report.html
```

## Related Documentation

- [Robot Framework Guide](../../05-advanced/11-robot-framework-guide.md)
- [Unit Testing Guide](../../05-advanced/10-unit-testing-guide.md)
- [openbmc-test-automation Repository](https://github.com/openbmc/openbmc-test-automation)
