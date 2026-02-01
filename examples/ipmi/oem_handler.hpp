/**
 * OEM IPMI Handler Header
 *
 * Defines OEM-specific IPMI commands and structures.
 */

#pragma once

#include <ipmid/api-types.hpp>
#include <cstdint>

namespace myoem
{

// OEM Network Function - Use your IANA Enterprise Number
// For testing, use 0x30 (generic OEM)
// For production, register with IANA and use assigned NetFn
constexpr ipmi::NetFn netFnOem = static_cast<ipmi::NetFn>(0x30);

// OEM Command Codes
namespace cmd
{
    // Information commands (0x01-0x0F)
    constexpr uint8_t getVersion = 0x01;
    constexpr uint8_t setLed = 0x02;
    constexpr uint8_t getBoardInfo = 0x03;

    // Configuration commands (0x10-0x1F)
    constexpr uint8_t setConfig = 0x10;
    constexpr uint8_t getConfig = 0x11;

    // Diagnostic commands (0x20-0x2F)
    constexpr uint8_t runDiagnostic = 0x20;
    constexpr uint8_t getDiagnosticResult = 0x21;

    // Manufacturing commands (0x80-0x8F)
    constexpr uint8_t mfgSetSerial = 0x80;
    constexpr uint8_t mfgSetMac = 0x81;
}

// Version info structure
struct VersionInfo
{
    uint8_t major;
    uint8_t minor;
    uint8_t patch;
};

// Board info structure
struct BoardInfo
{
    uint8_t boardType;
    uint8_t boardRevision;
    uint8_t cpuCount;
    uint8_t dimmSlots;
    uint16_t maxPower;
};

// LED identifiers
enum class LedId : uint8_t
{
    identify = 0,
    fault = 1,
    power = 2,
    status = 3
};

// LED states
enum class LedState : uint8_t
{
    off = 0,
    on = 1,
    blink = 2
};

// Configuration indices
enum class ConfigIndex : uint8_t
{
    bootMode = 0,
    fanPolicy = 1,
    powerPolicy = 2,
    debugLevel = 3
};

// Function to register all OEM handlers
void registerHandlers();

} // namespace myoem
