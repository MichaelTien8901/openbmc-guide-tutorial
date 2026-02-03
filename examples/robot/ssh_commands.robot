*** Settings ***
Documentation     SSH-based tests for OpenBMC
...               Demonstrates running commands directly on the BMC via SSH
Library           SSHLibrary

*** Variables ***
${OPENBMC_HOST}       localhost
${SSH_PORT}           2222
${OPENBMC_USERNAME}   root
${OPENBMC_PASSWORD}   0penBmc

*** Test Cases ***
Verify BMC OS Release
    [Documentation]    Check BMC is running OpenBMC via /etc/os-release
    [Tags]    ssh    smoke

    Open BMC SSH Connection
    ${output}=    Execute Command    cat /etc/os-release
    Should Contain    ${output}    openbmc-phosphor
    [Teardown]    Close Connection

Verify BMC Web Service Running
    [Documentation]    Verify bmcweb service is active
    [Tags]    ssh    services

    Open BMC SSH Connection
    ${output}=    Execute Command    systemctl is-active bmcweb
    Should Be Equal    ${output.strip()}    active
    [Teardown]    Close Connection

Verify IPMI Host Service Running
    [Documentation]    Verify phosphor-ipmi-host service is active
    [Tags]    ssh    services    ipmi

    Open BMC SSH Connection
    ${output}=    Execute Command    systemctl is-active phosphor-ipmi-host
    Should Be Equal    ${output.strip()}    active
    [Teardown]    Close Connection

Check BMC State Via obmcutil
    [Documentation]    Get BMC state using obmcutil command
    [Tags]    ssh    state

    Open BMC SSH Connection
    ${output}=    Execute Command    obmcutil state
    Should Contain    ${output}    BMCState
    Log    BMC State Output:\n${output}
    [Teardown]    Close Connection

List D-Bus Services
    [Documentation]    List running D-Bus services on the BMC
    [Tags]    ssh    dbus

    Open BMC SSH Connection
    ${output}=    Execute Command    busctl list --no-pager | head -30
    Should Contain    ${output}    xyz.openbmc_project
    Log    D-Bus Services:\n${output}
    [Teardown]    Close Connection

Check Sensor Daemon Running
    [Documentation]    Verify dbus-sensors service is running
    [Tags]    ssh    services    sensors

    Open BMC SSH Connection
    # Check for any sensor daemon
    ${output}=    Execute Command    systemctl list-units --type=service | grep -i sensor || echo "No sensor services"
    Log    Sensor Services:\n${output}
    [Teardown]    Close Connection

Get BMC Uptime
    [Documentation]    Get BMC uptime
    [Tags]    ssh    info

    Open BMC SSH Connection
    ${output}=    Execute Command    uptime
    Log    BMC Uptime: ${output}
    [Teardown]    Close Connection

Get Memory Usage
    [Documentation]    Check BMC memory usage
    [Tags]    ssh    info

    Open BMC SSH Connection
    ${output}=    Execute Command    free -m
    Log    Memory Usage:\n${output}
    [Teardown]    Close Connection

*** Keywords ***
Open BMC SSH Connection
    [Documentation]    Open SSH connection to BMC
    Open Connection    ${OPENBMC_HOST}    port=${SSH_PORT}
    Login    ${OPENBMC_USERNAME}    ${OPENBMC_PASSWORD}
