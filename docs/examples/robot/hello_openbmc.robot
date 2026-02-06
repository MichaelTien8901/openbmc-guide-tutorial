*** Settings ***
Documentation     Hello World test for OpenBMC - demonstrates basic Robot Framework patterns
...               Run with: robot -v OPENBMC_HOST:localhost -v HTTPS_PORT:2443 hello_openbmc.robot
Library           Collections
Library           RequestsLibrary

*** Variables ***
${OPENBMC_HOST}       localhost
${HTTPS_PORT}         2443
${OPENBMC_USERNAME}   root
${OPENBMC_PASSWORD}   0penBmc
${REDFISH_BASE}       /redfish/v1

*** Test Cases ***
Verify Redfish Service Root Is Accessible
    [Documentation]    Verify the Redfish service root responds correctly
    [Tags]    smoke    redfish

    # Create HTTPS session (verify=False for self-signed certs)
    Create Session    openbmc    https://${OPENBMC_HOST}:${HTTPS_PORT}
    ...    verify=${False}

    # GET the service root
    ${resp}=    GET On Session    openbmc    ${REDFISH_BASE}
    ...    expected_status=200

    # Verify response structure
    Should Be Equal As Strings    ${resp.status_code}    200
    Dictionary Should Contain Key    ${resp.json()}    @odata.id
    Dictionary Should Contain Key    ${resp.json()}    RedfishVersion

    Log    Redfish Version: ${resp.json()["RedfishVersion"]}

Verify BMC Manager Resource
    [Documentation]    Verify BMC Manager resource is accessible with authentication
    [Tags]    smoke    redfish    manager

    # Create authenticated session
    ${auth}=    Create List    ${OPENBMC_USERNAME}    ${OPENBMC_PASSWORD}
    Create Session    openbmc    https://${OPENBMC_HOST}:${HTTPS_PORT}
    ...    auth=${auth}    verify=${False}

    # GET the BMC manager resource
    ${resp}=    GET On Session    openbmc    ${REDFISH_BASE}/Managers/bmc
    ...    expected_status=200

    # Verify BMC state
    ${json}=    Set Variable    ${resp.json()}
    Should Be Equal As Strings    ${json["Status"]["State"]}    Enabled
    Should Be Equal As Strings    ${json["Status"]["Health"]}    OK

    Log    BMC Firmware Version: ${json["FirmwareVersion"]}

Verify Systems Collection
    [Documentation]    Verify the Systems collection contains expected member
    [Tags]    smoke    redfish    system

    ${auth}=    Create List    ${OPENBMC_USERNAME}    ${OPENBMC_PASSWORD}
    Create Session    openbmc    https://${OPENBMC_HOST}:${HTTPS_PORT}
    ...    auth=${auth}    verify=${False}

    ${resp}=    GET On Session    openbmc    ${REDFISH_BASE}/Systems
    ...    expected_status=200

    # Verify at least one system member exists
    ${members}=    Get From Dictionary    ${resp.json()}    Members
    ${count}=    Get Length    ${members}
    Should Be True    ${count} >= 1    Expected at least one system member

*** Keywords ***
Get Redfish Resource
    [Documentation]    Helper keyword to GET a Redfish resource with authentication
    [Arguments]    ${path}
    ${auth}=    Create List    ${OPENBMC_USERNAME}    ${OPENBMC_PASSWORD}
    Create Session    openbmc    https://${OPENBMC_HOST}:${HTTPS_PORT}
    ...    auth=${auth}    verify=${False}
    ${resp}=    GET On Session    openbmc    ${path}
    [Return]    ${resp}
