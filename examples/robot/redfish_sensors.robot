*** Settings ***
Documentation     Redfish sensor tests for OpenBMC
...               Demonstrates reading sensor data via Redfish API
Library           Collections
Library           RequestsLibrary

*** Variables ***
${OPENBMC_HOST}       localhost
${HTTPS_PORT}         2443
${OPENBMC_USERNAME}   root
${OPENBMC_PASSWORD}   0penBmc
${REDFISH_BASE}       /redfish/v1

*** Test Cases ***
Get Chassis Thermal Sensors
    [Documentation]    Read thermal sensor data from Redfish Chassis
    [Tags]    sensors    thermal    redfish

    ${session}=    Create Authenticated Session

    # Get Chassis collection to find chassis ID
    ${resp}=    GET On Session    ${session}    ${REDFISH_BASE}/Chassis
    ...    expected_status=200

    ${members}=    Get From Dictionary    ${resp.json()}    Members
    Should Not Be Empty    ${members}    No chassis found

    # Get first chassis thermal data
    ${chassis_uri}=    Get From Dictionary    ${members}[0]    @odata.id
    ${thermal_resp}=    GET On Session    ${session}    ${chassis_uri}/Thermal
    ...    expected_status=any

    Run Keyword If    ${thermal_resp.status_code} == 200
    ...    Log Thermal Data    ${thermal_resp.json()}
    ...    ELSE    Log    Thermal resource not available (status: ${thermal_resp.status_code})

Get Chassis Power Sensors
    [Documentation]    Read power sensor data from Redfish Chassis
    [Tags]    sensors    power    redfish

    ${session}=    Create Authenticated Session

    ${resp}=    GET On Session    ${session}    ${REDFISH_BASE}/Chassis
    ...    expected_status=200

    ${members}=    Get From Dictionary    ${resp.json()}    Members
    ${chassis_uri}=    Get From Dictionary    ${members}[0]    @odata.id

    ${power_resp}=    GET On Session    ${session}    ${chassis_uri}/Power
    ...    expected_status=any

    Run Keyword If    ${power_resp.status_code} == 200
    ...    Log Power Data    ${power_resp.json()}
    ...    ELSE    Log    Power resource not available (status: ${power_resp.status_code})

Get Sensor Collection Via TelemetryService
    [Documentation]    Read sensors via Redfish TelemetryService (if available)
    [Tags]    sensors    telemetry    redfish

    ${session}=    Create Authenticated Session

    # Check if TelemetryService is available
    ${resp}=    GET On Session    ${session}    ${REDFISH_BASE}/TelemetryService
    ...    expected_status=any

    Run Keyword If    ${resp.status_code} == 200
    ...    Log    TelemetryService available
    ...    ELSE    Skip    TelemetryService not available on this BMC

*** Keywords ***
Create Authenticated Session
    [Documentation]    Create and return an authenticated Redfish session
    ${auth}=    Create List    ${OPENBMC_USERNAME}    ${OPENBMC_PASSWORD}
    Create Session    redfish    https://${OPENBMC_HOST}:${HTTPS_PORT}
    ...    auth=${auth}    verify=${False}
    [Return]    redfish

Log Thermal Data
    [Documentation]    Log temperature sensor readings
    [Arguments]    ${thermal_json}
    ${temps}=    Get From Dictionary    ${thermal_json}    Temperatures    default=@{EMPTY}
    FOR    ${temp}    IN    @{temps}
        ${name}=    Get From Dictionary    ${temp}    Name    default=Unknown
        ${reading}=    Get From Dictionary    ${temp}    ReadingCelsius    default=N/A
        Log    Sensor: ${name} = ${reading}°C
    END

Log Power Data
    [Documentation]    Log power sensor readings
    [Arguments]    ${power_json}
    ${voltages}=    Get From Dictionary    ${power_json}    Voltages    default=@{EMPTY}
    FOR    ${voltage}    IN    @{voltages}
        ${name}=    Get From Dictionary    ${voltage}    Name    default=Unknown
        ${reading}=    Get From Dictionary    ${voltage}    ReadingVolts    default=N/A
        Log    Voltage: ${name} = ${reading}V
    END
