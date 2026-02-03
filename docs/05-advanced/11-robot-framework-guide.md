---
layout: default
title: Robot Framework Guide
parent: Advanced Topics
nav_order: 11
difficulty: advanced
prerequisites:
  - first-build
  - redfish-guide
---

# Robot Framework Guide
{: .no_toc }

Integration testing for OpenBMC using Robot Framework.
{: .fs-6 .fw-300 }

## Table of Contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

## Overview

Robot Framework is the standard integration testing framework for OpenBMC. The `openbmc-test-automation` repository contains comprehensive tests for:

- Redfish API validation
- IPMI command testing
- Power state management
- Sensor and inventory verification
- Firmware update testing

This guide covers setting up Robot Framework and writing tests for OpenBMC.

### Unit Tests vs Integration Tests

| Aspect | Unit Tests (GTest) | Integration Tests (Robot) |
|--------|-------------------|---------------------------|
| **Scope** | Single function/class | Full system behavior |
| **Dependencies** | Mocked | Real services |
| **Speed** | Fast (ms) | Slower (seconds) |
| **Environment** | Build machine | Running BMC (QEMU/HW) |
| **Purpose** | Code correctness | System behavior |

---

## Environment Setup

### Install Robot Framework

```bash
# Install Python 3 and pip
sudo apt install python3 python3-pip

# Install Robot Framework
pip3 install robotframework

# Install additional libraries
pip3 install robotframework-sshlibrary
pip3 install robotframework-requests
pip3 install robotframework-httplibrary

# Verify installation
robot --version
```

### Clone openbmc-test-automation

```bash
# Clone the test repository
git clone https://github.com/openbmc/openbmc-test-automation.git
cd openbmc-test-automation

# Install Python dependencies
pip3 install -r requirements.txt
```

### Environment Variables

Set up connection parameters:

```bash
# BMC connection (QEMU example)
export OPENBMC_HOST=localhost
export OPENBMC_SSH_PORT=2222
export OPENBMC_HTTPS_PORT=2443

# Credentials
export OPENBMC_USERNAME=root
export OPENBMC_PASSWORD=0penBmc

# For real hardware
export OPENBMC_HOST=192.168.1.100
export OPENBMC_SSH_PORT=22
export OPENBMC_HTTPS_PORT=443
```

---

## Hello World Test

### Minimal Robot Test

Create `hello_openbmc.robot`:

```robot
*** Settings ***
Documentation     Hello World test for OpenBMC
Library           Collections
Library           RequestsLibrary

*** Variables ***
${OPENBMC_HOST}       localhost
${OPENBMC_PORT}       2443
${OPENBMC_USERNAME}   root
${OPENBMC_PASSWORD}   0penBmc

*** Test Cases ***
Verify BMC Redfish Service Root
    [Documentation]    Verify Redfish service is accessible
    [Tags]    smoke

    # Create session
    Create Session    openbmc    https://${OPENBMC_HOST}:${OPENBMC_PORT}
    ...    verify=${False}

    # Get service root
    ${resp}=    GET On Session    openbmc    /redfish/v1
    ...    expected_status=200

    # Verify response
    Should Be Equal As Strings    ${resp.status_code}    200
    Dictionary Should Contain Key    ${resp.json()}    @odata.id

Verify BMC Manager Resource
    [Documentation]    Verify BMC Manager is accessible
    [Tags]    smoke

    Create Session    openbmc    https://${OPENBMC_HOST}:${OPENBMC_PORT}
    ...    auth=${OPENBMC_AUTH}    verify=${False}

    ${resp}=    GET On Session    openbmc    /redfish/v1/Managers/bmc
    ...    expected_status=200

    Should Be Equal As Strings    ${resp.json()["Status"]["State"]}    Enabled

*** Keywords ***
${OPENBMC_AUTH}
    [Return]    ${OPENBMC_USERNAME}    ${OPENBMC_PASSWORD}
```

### Running the Test

```bash
# Start QEMU with OpenBMC (in another terminal)
qemu-system-arm -m 1G -M ast2600-evb -nographic \
    -drive file=obmc-phosphor-image-ast2600-evb.static.mtd,format=raw,if=mtd \
    -net nic -net user,hostfwd=tcp::2222-:22,hostfwd=tcp::2443-:443

# Run the test
robot hello_openbmc.robot

# Run with verbose output
robot -L DEBUG hello_openbmc.robot
```

### Test Output

Robot generates three output files:
- `output.xml` - Machine-readable results
- `log.html` - Detailed execution log
- `report.html` - Summary report

```bash
# View report
xdg-open report.html
```

---

## Robot Test File Structure

### File Organization

```robot
*** Settings ***
Documentation     Description of test suite
Library           LibraryName
Resource          resource_file.robot
Suite Setup       Setup Keyword
Suite Teardown    Teardown Keyword

*** Variables ***
${VARIABLE}       value
@{LIST}           item1    item2
&{DICT}           key1=value1    key2=value2

*** Test Cases ***
Test Case Name
    [Documentation]    Test description
    [Tags]             tag1    tag2
    Keyword 1
    Keyword 2    ${argument}

*** Keywords ***
Custom Keyword
    [Arguments]    ${arg1}    ${arg2}
    Log    ${arg1}
    [Return]    ${result}
```

### Common Settings

| Setting | Purpose |
|---------|---------|
| `Library` | Import Python/Robot library |
| `Resource` | Import resource file with keywords |
| `Suite Setup` | Run before all tests |
| `Suite Teardown` | Run after all tests |
| `Test Setup` | Run before each test |
| `Test Teardown` | Run after each test |

---

## openbmc-test-automation Structure

### Directory Layout

```
openbmc-test-automation/
├── robot_framework/           # Test suites
│   ├── redfish/              # Redfish API tests
│   ├── ipmi/                 # IPMI tests
│   ├── ssh/                  # SSH-based tests
│   └── gui/                  # Web UI tests
├── lib/                      # Keyword libraries
│   ├── bmc_redfish.py       # Redfish keywords
│   ├── ipmi_client.py       # IPMI keywords
│   └── utils.py             # Utility functions
├── data/                     # Test data
├── templates/                # Configuration templates
└── requirements.txt          # Python dependencies
```

### Key Resource Files

| File | Purpose |
|------|---------|
| `lib/resource.robot` | Common variables and keywords |
| `lib/bmc_redfish_resource.robot` | Redfish-specific keywords |
| `lib/ipmi_client.robot` | IPMI keywords |
| `lib/connection_client.robot` | SSH connection handling |

### Using Existing Keywords

```robot
*** Settings ***
Resource    ../lib/resource.robot
Resource    ../lib/bmc_redfish_resource.robot

*** Test Cases ***
Test Power On Host
    [Documentation]    Power on the host via Redfish
    [Tags]    power

    Redfish Power On
    Wait Until Keyword Succeeds    3 min    10 sec
    ...    Is Host Running
```

---

## Test Execution

### Running Tests Against QEMU

```bash
# Start QEMU (terminal 1)
qemu-system-arm -m 1G -M ast2600-evb -nographic \
    -drive file=obmc-phosphor-image.static.mtd,format=raw,if=mtd \
    -net nic \
    -net user,hostfwd=tcp::2222-:22,hostfwd=tcp::2443-:443,hostfwd=udp::2623-:623

# Run tests (terminal 2)
cd openbmc-test-automation

robot -v OPENBMC_HOST:localhost \
      -v SSH_PORT:2222 \
      -v HTTPS_PORT:2443 \
      -v OPENBMC_USERNAME:root \
      -v OPENBMC_PASSWORD:0penBmc \
      redfish/service_root/test_service_root.robot
```

### Running Tests Against Real Hardware

```bash
robot -v OPENBMC_HOST:192.168.1.100 \
      -v SSH_PORT:22 \
      -v HTTPS_PORT:443 \
      -v OPENBMC_USERNAME:root \
      -v OPENBMC_PASSWORD:0penBmc \
      redfish/service_root/test_service_root.robot
```

### Running Specific Test Suites

```bash
# Run single test file
robot redfish/account_service/test_accounts.robot

# Run tests with specific tag
robot --include smoke redfish/

# Run tests excluding a tag
robot --exclude destructive redfish/

# Run specific test case
robot --test "Verify Service Root" redfish/service_root/
```

### Test Output Options

```bash
# Custom output directory
robot -d results/ test_suite.robot

# Custom report name
robot -r custom_report.html test_suite.robot

# Log level
robot -L DEBUG test_suite.robot
robot -L TRACE test_suite.robot
```

---

## Common Test Patterns

### Redfish API Test

```robot
*** Settings ***
Library           RequestsLibrary
Library           Collections

*** Variables ***
${REDFISH_BASE}    /redfish/v1

*** Test Cases ***
Get System Information Via Redfish
    [Documentation]    Retrieve system info via Redfish
    [Tags]    redfish    system

    # Authenticate
    ${auth}=    Create List    ${OPENBMC_USERNAME}    ${OPENBMC_PASSWORD}
    Create Session    bmc    https://${OPENBMC_HOST}:${HTTPS_PORT}
    ...    auth=${auth}    verify=${False}

    # Get system resource
    ${resp}=    GET On Session    bmc    ${REDFISH_BASE}/Systems/system
    Should Be Equal As Integers    ${resp.status_code}    200

    # Verify fields
    ${json}=    Set Variable    ${resp.json()}
    Should Be Equal    ${json["PowerState"]}    On
    Should Not Be Empty    ${json["SerialNumber"]}

Patch System Asset Tag
    [Documentation]    Update system asset tag
    [Tags]    redfish    system    patch

    ${auth}=    Create List    ${OPENBMC_USERNAME}    ${OPENBMC_PASSWORD}
    Create Session    bmc    https://${OPENBMC_HOST}:${HTTPS_PORT}
    ...    auth=${auth}    verify=${False}

    # Update asset tag
    ${payload}=    Create Dictionary    AssetTag=TestAsset123
    ${headers}=    Create Dictionary    Content-Type=application/json

    ${resp}=    PATCH On Session    bmc    ${REDFISH_BASE}/Systems/system
    ...    json=${payload}    headers=${headers}

    Should Be Equal As Integers    ${resp.status_code}    200
```

### IPMI Command Test

```robot
*** Settings ***
Library           OperatingSystem
Library           Process

*** Variables ***
${IPMI_CMD}    ipmitool -I lanplus -H ${OPENBMC_HOST} -p 623 -U ${OPENBMC_USERNAME} -P ${OPENBMC_PASSWORD}

*** Test Cases ***
Get BMC Info Via IPMI
    [Documentation]    Get BMC device info via IPMI
    [Tags]    ipmi

    ${result}=    Run Process    ${IPMI_CMD} mc info    shell=True
    Should Be Equal As Integers    ${result.rc}    0
    Should Contain    ${result.stdout}    Firmware Revision

Get Sensor List Via IPMI
    [Documentation]    List sensors via IPMI
    [Tags]    ipmi    sensors

    ${result}=    Run Process    ${IPMI_CMD} sensor list    shell=True
    Should Be Equal As Integers    ${result.rc}    0
    Should Not Be Empty    ${result.stdout}

Chassis Power Status
    [Documentation]    Check chassis power status
    [Tags]    ipmi    power

    ${result}=    Run Process    ${IPMI_CMD} chassis power status    shell=True
    Should Be Equal As Integers    ${result.rc}    0
    Should Match Regexp    ${result.stdout}    Chassis Power is (on|off)
```

### SSH-Based Test

```robot
*** Settings ***
Library           SSHLibrary

*** Test Cases ***
Verify BMC Version Via SSH
    [Documentation]    Check BMC version via SSH
    [Tags]    ssh

    # Connect to BMC
    Open Connection    ${OPENBMC_HOST}    port=${SSH_PORT}
    Login    ${OPENBMC_USERNAME}    ${OPENBMC_PASSWORD}

    # Get version info
    ${output}=    Execute Command    cat /etc/os-release
    Should Contain    ${output}    openbmc-phosphor

    # Check service status
    ${output}=    Execute Command    systemctl is-active bmcweb
    Should Be Equal    ${output.strip()}    active

    [Teardown]    Close Connection

Execute obmcutil Command
    [Documentation]    Run obmcutil via SSH
    [Tags]    ssh    power

    Open Connection    ${OPENBMC_HOST}    port=${SSH_PORT}
    Login    ${OPENBMC_USERNAME}    ${OPENBMC_PASSWORD}

    ${output}=    Execute Command    obmcutil state
    Should Contain    ${output}    BMCState

    [Teardown]    Close Connection
```

---

## Example Test Files

Working examples are available in the [examples/robot](https://github.com/MichaelTien8901/openbmc-guide-tutorial/tree/master/examples/robot) directory:

- `hello_openbmc.robot` - Basic connectivity and Redfish authentication tests
- `redfish_sensors.robot` - Sensor reading and validation tests
- `ssh_commands.robot` - SSH command execution tests

---

## Troubleshooting

### Common Issues

| Issue | Cause | Solution |
|-------|-------|----------|
| Connection refused | BMC not running | Start QEMU or check network |
| SSL certificate error | Self-signed cert | Use `verify=${False}` |
| Authentication failed | Wrong credentials | Verify username/password |
| Timeout waiting for host | Slow boot | Increase timeout values |
| IPMI connection failed | Port not forwarded | Check QEMU port forwarding (UDP 623) |

### Debug Tips

```bash
# Run with debug logging
robot -L DEBUG test.robot

# Trace library calls
robot -L TRACE test.robot

# Dry run (syntax check)
robot --dryrun test.robot

# List tests without running
robot --list test.robot
```

### Checking BMC State

```bash
# SSH to BMC
ssh -p 2222 root@localhost

# Check service status
systemctl status bmcweb
systemctl status phosphor-ipmi-host

# View logs
journalctl -u bmcweb -f
```

---

## Next Steps

- [Unit Testing Guide]({% link docs/05-advanced/10-unit-testing-guide.md %}) - GTest/GMock for unit tests
- [Verification Guide]({% link docs/06-porting/05-verification.md %}) - Complete testing checklist
- [Redfish Guide]({% link docs/04-interfaces/02-redfish-guide.md %}) - Redfish API details

---

## References

- [Robot Framework Documentation](https://robotframework.org/robotframework/)
- [openbmc-test-automation Repository](https://github.com/openbmc/openbmc-test-automation)
- [RequestsLibrary Documentation](https://marketsquare.github.io/robotframework-requests/)
- [SSHLibrary Documentation](https://robotframework.org/SSHLibrary/)

---

{: .note }
**Tested on**: Robot Framework 6.x with OpenBMC on QEMU ast2600-evb
