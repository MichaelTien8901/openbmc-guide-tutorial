/**
 * OEM IPMI Handler Implementation
 *
 * Example OEM IPMI command handlers for OpenBMC.
 *
 * Source Reference:
 *   - Based on patterns from: https://github.com/openbmc/phosphor-host-ipmid
 *   - IPMI API: https://github.com/openbmc/phosphor-host-ipmid/blob/master/include/ipmid/api.hpp
 *   - Example handlers: https://github.com/openbmc/phosphor-host-ipmid/blob/master/chassishandler.cpp
 *
 * Build with OpenBMC SDK:
 *   mkdir build && cd build
 *   cmake ..
 *   make
 */

#include "oem_handler.hpp"

#include <ipmid/api.hpp>
#include <ipmid/utils.hpp>
#include <phosphor-logging/log.hpp>
#include <sdbusplus/bus.hpp>

#include <array>
#include <map>
#include <string>

using namespace phosphor::logging;

namespace myoem
{

// Simulated configuration storage (in production, use persistent storage)
static std::map<uint8_t, uint8_t> configStorage;

// Current version
static constexpr VersionInfo currentVersion = {1, 0, 0};

// Board information (would be read from hardware in production)
static constexpr BoardInfo boardInfo = {
    .boardType = 0x01,      // Server
    .boardRevision = 0x02,  // Rev B
    .cpuCount = 2,
    .dimmSlots = 16,
    .maxPower = 1000        // 1000W
};

/**
 * Get OEM Version
 *
 * Command: 0x01
 * Request: None
 * Response: [major] [minor] [patch]
 */
ipmi::RspType<uint8_t, uint8_t, uint8_t>
    ipmiOemGetVersion()
{
    log<level::INFO>("OEM Get Version called");

    return ipmi::responseSuccess(
        currentVersion.major,
        currentVersion.minor,
        currentVersion.patch);
}

/**
 * Set LED State
 *
 * Command: 0x02
 * Request: [led_id] [state]
 * Response: None
 */
ipmi::RspType<> ipmiOemSetLed(uint8_t ledId, uint8_t state)
{
    log<level::INFO>("OEM Set LED",
        entry("LED_ID=%d", ledId),
        entry("STATE=%d", state));

    // Validate LED ID
    if (ledId > static_cast<uint8_t>(LedId::status))
    {
        log<level::ERR>("Invalid LED ID", entry("LED_ID=%d", ledId));
        return ipmi::responseParmOutOfRange();
    }

    // Validate state
    if (state > static_cast<uint8_t>(LedState::blink))
    {
        log<level::ERR>("Invalid LED state", entry("STATE=%d", state));
        return ipmi::responseParmOutOfRange();
    }

    // Map LED ID to D-Bus path
    std::string ledPath;
    switch (static_cast<LedId>(ledId))
    {
        case LedId::identify:
            ledPath = "/xyz/openbmc_project/led/groups/enclosure_identify";
            break;
        case LedId::fault:
            ledPath = "/xyz/openbmc_project/led/groups/enclosure_fault";
            break;
        case LedId::power:
            ledPath = "/xyz/openbmc_project/led/groups/power";
            break;
        case LedId::status:
            ledPath = "/xyz/openbmc_project/led/groups/status";
            break;
    }

    // Set LED via D-Bus
    try
    {
        auto bus = sdbusplus::bus::new_default();
        auto method = bus.new_method_call(
            "xyz.openbmc_project.LED.GroupManager",
            ledPath.c_str(),
            "org.freedesktop.DBus.Properties",
            "Set");

        method.append("xyz.openbmc_project.Led.Group");
        method.append("Asserted");
        method.append(std::variant<bool>(state != 0));

        bus.call(method);
    }
    catch (const sdbusplus::exception_t& e)
    {
        log<level::ERR>("Failed to set LED",
            entry("PATH=%s", ledPath.c_str()),
            entry("ERROR=%s", e.what()));
        return ipmi::responseUnspecifiedError();
    }

    return ipmi::responseSuccess();
}

/**
 * Get Board Info
 *
 * Command: 0x03
 * Request: None
 * Response: [type] [revision] [cpu_count] [dimm_slots] [max_power_lo] [max_power_hi]
 */
ipmi::RspType<uint8_t, uint8_t, uint8_t, uint8_t, uint8_t, uint8_t>
    ipmiOemGetBoardInfo()
{
    log<level::INFO>("OEM Get Board Info called");

    return ipmi::responseSuccess(
        boardInfo.boardType,
        boardInfo.boardRevision,
        boardInfo.cpuCount,
        boardInfo.dimmSlots,
        static_cast<uint8_t>(boardInfo.maxPower & 0xFF),
        static_cast<uint8_t>((boardInfo.maxPower >> 8) & 0xFF));
}

/**
 * Set Configuration
 *
 * Command: 0x10
 * Request: [index] [value]
 * Response: None
 */
ipmi::RspType<> ipmiOemSetConfig(uint8_t index, uint8_t value)
{
    log<level::INFO>("OEM Set Config",
        entry("INDEX=%d", index),
        entry("VALUE=%d", value));

    // Validate index
    if (index > static_cast<uint8_t>(ConfigIndex::debugLevel))
    {
        return ipmi::responseParmOutOfRange();
    }

    // Store configuration
    configStorage[index] = value;

    // In production, persist to storage
    // Example: write to /var/lib/myoem/config

    return ipmi::responseSuccess();
}

/**
 * Get Configuration
 *
 * Command: 0x11
 * Request: [index]
 * Response: [value]
 */
ipmi::RspType<uint8_t> ipmiOemGetConfig(uint8_t index)
{
    log<level::INFO>("OEM Get Config", entry("INDEX=%d", index));

    // Validate index
    if (index > static_cast<uint8_t>(ConfigIndex::debugLevel))
    {
        return ipmi::responseParmOutOfRange();
    }

    // Get configuration (default to 0 if not set)
    uint8_t value = 0;
    auto it = configStorage.find(index);
    if (it != configStorage.end())
    {
        value = it->second;
    }

    return ipmi::responseSuccess(value);
}

/**
 * Run Diagnostic
 *
 * Command: 0x20
 * Request: [test_id]
 * Response: None (async)
 */
ipmi::RspType<> ipmiOemRunDiagnostic(uint8_t testId)
{
    log<level::INFO>("OEM Run Diagnostic", entry("TEST_ID=%d", testId));

    // Validate test ID
    if (testId > 10)
    {
        return ipmi::responseParmOutOfRange();
    }

    // In production, trigger diagnostic test asynchronously
    // Store result for later retrieval with getDiagnosticResult

    return ipmi::responseSuccess();
}

/**
 * Get Diagnostic Result
 *
 * Command: 0x21
 * Request: [test_id]
 * Response: [status] [result_code]
 */
ipmi::RspType<uint8_t, uint8_t> ipmiOemGetDiagnosticResult(uint8_t testId)
{
    log<level::INFO>("OEM Get Diagnostic Result", entry("TEST_ID=%d", testId));

    // Validate test ID
    if (testId > 10)
    {
        return ipmi::responseParmOutOfRange();
    }

    // In production, retrieve actual diagnostic result
    uint8_t status = 0x01;  // Complete
    uint8_t result = 0x00;  // Pass

    return ipmi::responseSuccess(status, result);
}

/**
 * Register all OEM handlers
 */
void registerHandlers()
{
    log<level::INFO>("Registering OEM IPMI handlers");

    // Get Version (User privilege)
    ipmi::registerHandler(
        ipmi::prioOemBase,
        netFnOem,
        cmd::getVersion,
        ipmi::Privilege::User,
        ipmiOemGetVersion);

    // Set LED (Operator privilege)
    ipmi::registerHandler(
        ipmi::prioOemBase,
        netFnOem,
        cmd::setLed,
        ipmi::Privilege::Operator,
        ipmiOemSetLed);

    // Get Board Info (User privilege)
    ipmi::registerHandler(
        ipmi::prioOemBase,
        netFnOem,
        cmd::getBoardInfo,
        ipmi::Privilege::User,
        ipmiOemGetBoardInfo);

    // Set Config (Admin privilege)
    ipmi::registerHandler(
        ipmi::prioOemBase,
        netFnOem,
        cmd::setConfig,
        ipmi::Privilege::Admin,
        ipmiOemSetConfig);

    // Get Config (User privilege)
    ipmi::registerHandler(
        ipmi::prioOemBase,
        netFnOem,
        cmd::getConfig,
        ipmi::Privilege::User,
        ipmiOemGetConfig);

    // Run Diagnostic (Admin privilege)
    ipmi::registerHandler(
        ipmi::prioOemBase,
        netFnOem,
        cmd::runDiagnostic,
        ipmi::Privilege::Admin,
        ipmiOemRunDiagnostic);

    // Get Diagnostic Result (User privilege)
    ipmi::registerHandler(
        ipmi::prioOemBase,
        netFnOem,
        cmd::getDiagnosticResult,
        ipmi::Privilege::User,
        ipmiOemGetDiagnosticResult);

    log<level::INFO>("OEM IPMI handlers registered successfully");
}

} // namespace myoem

/**
 * Library initialization
 * Called when the shared library is loaded by ipmid
 */
void registerMyOemHandlers() __attribute__((constructor));
void registerMyOemHandlers()
{
    myoem::registerHandlers();
}
