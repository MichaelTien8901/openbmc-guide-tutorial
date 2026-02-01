/**
 * Sensor Reader Utility
 *
 * Reads and displays sensor values from D-Bus.
 * Demonstrates using Object Mapper to discover sensors.
 *
 * Source Reference:
 *   - dbus-sensors: https://github.com/openbmc/dbus-sensors
 *   - Sensor interfaces: https://github.com/openbmc/phosphor-dbus-interfaces/tree/master/yaml/xyz/openbmc_project/Sensor
 *   - Object Mapper: https://github.com/openbmc/phosphor-objmgr
 *
 * Build with SDK:
 *   $CXX -std=c++20 sensor_reader.cpp -o sensor_reader \
 *       $(pkg-config --cflags --libs sdbusplus)
 *
 * Usage:
 *   ./sensor_reader              # List all sensors
 *   ./sensor_reader temperature  # List temperature sensors
 *   ./sensor_reader voltage      # List voltage sensors
 *   ./sensor_reader power        # List power sensors
 *   ./sensor_reader fan          # List fan sensors
 */

#include <sdbusplus/bus.hpp>
#include <iostream>
#include <iomanip>
#include <string>
#include <vector>
#include <map>
#include <variant>

constexpr auto objectMapperService = "xyz.openbmc_project.ObjectMapper";
constexpr auto objectMapperPath = "/xyz/openbmc_project/object_mapper";
constexpr auto objectMapperInterface = "xyz.openbmc_project.ObjectMapper";
constexpr auto sensorValueInterface = "xyz.openbmc_project.Sensor.Value";
constexpr auto sensorBasePath = "/xyz/openbmc_project/sensors";

// Get unit string for display
std::string getUnitDisplay(const std::string& path)
{
    if (path.find("/temperature/") != std::string::npos)
        return "°C";
    if (path.find("/voltage/") != std::string::npos)
        return "V";
    if (path.find("/power/") != std::string::npos)
        return "W";
    if (path.find("/current/") != std::string::npos)
        return "A";
    if (path.find("/fan_tach/") != std::string::npos)
        return "RPM";
    if (path.find("/fan_pwm/") != std::string::npos)
        return "%";
    return "";
}

// Extract sensor name from path
std::string getSensorName(const std::string& path)
{
    auto pos = path.rfind('/');
    if (pos != std::string::npos)
    {
        return path.substr(pos + 1);
    }
    return path;
}

// Get sensor type from path
std::string getSensorType(const std::string& path)
{
    // Extract type from /xyz/openbmc_project/sensors/<type>/<name>
    std::string prefix = "/xyz/openbmc_project/sensors/";
    if (path.find(prefix) == 0)
    {
        auto remainder = path.substr(prefix.length());
        auto pos = remainder.find('/');
        if (pos != std::string::npos)
        {
            return remainder.substr(0, pos);
        }
    }
    return "unknown";
}

int main(int argc, char* argv[])
{
    std::string filterType;
    if (argc > 1)
    {
        filterType = argv[1];
    }

    try
    {
        auto bus = sdbusplus::bus::new_default();

        // Build search path
        std::string searchPath = sensorBasePath;
        if (!filterType.empty() && filterType != "all")
        {
            searchPath += "/" + filterType;
        }

        // Use Object Mapper to find sensors
        auto method = bus.new_method_call(
            objectMapperService, objectMapperPath, objectMapperInterface,
            "GetSubTree");

        method.append(searchPath);
        method.append(0); // depth
        std::vector<std::string> interfaces = {sensorValueInterface};
        method.append(interfaces);

        auto reply = bus.call(method);

        // Parse response: map<path, map<service, interfaces>>
        std::map<std::string,
                 std::map<std::string, std::vector<std::string>>>
            results;
        reply.read(results);

        if (results.empty())
        {
            std::cout << "No sensors found";
            if (!filterType.empty())
            {
                std::cout << " of type: " << filterType;
            }
            std::cout << "\n";
            return 0;
        }

        // Print header
        std::cout << std::left << std::setw(30) << "Sensor"
                  << std::setw(12) << "Type"
                  << std::setw(15) << "Value"
                  << "Service" << "\n";
        std::cout << std::string(80, '-') << "\n";

        // Read and display each sensor
        for (const auto& [path, services] : results)
        {
            for (const auto& [service, ifaces] : services)
            {
                try
                {
                    // Get Value property
                    auto getProperty = bus.new_method_call(
                        service.c_str(), path.c_str(),
                        "org.freedesktop.DBus.Properties", "Get");
                    getProperty.append(sensorValueInterface, "Value");

                    auto propReply = bus.call(getProperty);
                    std::variant<double> valueVariant;
                    propReply.read(valueVariant);

                    double value = std::get<double>(valueVariant);
                    std::string unit = getUnitDisplay(path);
                    std::string name = getSensorName(path);
                    std::string type = getSensorType(path);

                    // Format value with unit
                    std::ostringstream valueStr;
                    valueStr << std::fixed << std::setprecision(2) << value
                             << " " << unit;

                    std::cout << std::left << std::setw(30) << name
                              << std::setw(12) << type
                              << std::setw(15) << valueStr.str()
                              << service << "\n";
                }
                catch (const std::exception& e)
                {
                    std::cout << std::left << std::setw(30) << getSensorName(path)
                              << std::setw(12) << getSensorType(path)
                              << std::setw(15) << "N/A"
                              << service << "\n";
                }
            }
        }

        std::cout << "\nTotal: " << results.size() << " sensors\n";
    }
    catch (const std::exception& e)
    {
        std::cerr << "Error: " << e.what() << "\n";
        return 1;
    }

    return 0;
}
