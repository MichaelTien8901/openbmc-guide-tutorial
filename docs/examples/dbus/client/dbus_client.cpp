/**
 * D-Bus Client Example
 *
 * Demonstrates how to:
 * - Connect to the system bus
 * - Read properties from D-Bus objects
 * - Call D-Bus methods
 * - Monitor property changes
 *
 * Source Reference:
 *   - sdbusplus library: https://github.com/openbmc/sdbusplus
 *   - Bus API: https://github.com/openbmc/sdbusplus/blob/master/include/sdbusplus/bus.hpp
 *   - Examples: https://github.com/openbmc/sdbusplus/tree/master/example
 *
 * Build with SDK:
 *   $CXX -std=c++20 dbus_client.cpp -o dbus_client \
 *       $(pkg-config --cflags --libs sdbusplus)
 */

#include <sdbusplus/bus.hpp>
#include <sdbusplus/message.hpp>
#include <iostream>
#include <variant>
#include <string>
#include <vector>
#include <map>

// Helper to print variant values
void printVariant(const std::variant<std::string, int64_t, uint64_t,
                                     double, bool>& value)
{
    std::visit([](auto&& arg) {
        std::cout << arg;
    }, value);
}

int main()
{
    try
    {
        // Connect to system bus
        auto bus = sdbusplus::bus::new_default();
        std::cout << "Connected to D-Bus system bus\n\n";

        // ========================================
        // Example 1: Read a property
        // ========================================
        std::cout << "=== Reading Host State ===\n";

        auto getMethod = bus.new_method_call(
            "xyz.openbmc_project.State.Host",       // Service name
            "/xyz/openbmc_project/state/host0",     // Object path
            "org.freedesktop.DBus.Properties",      // Interface
            "Get"                                    // Method
        );

        // Arguments: interface name, property name
        getMethod.append("xyz.openbmc_project.State.Host",
                        "CurrentHostState");

        auto reply = bus.call(getMethod);

        std::variant<std::string> hostState;
        reply.read(hostState);

        std::cout << "Current Host State: "
                  << std::get<std::string>(hostState) << "\n\n";

        // ========================================
        // Example 2: Get all properties
        // ========================================
        std::cout << "=== Getting All Properties ===\n";

        auto getAllMethod = bus.new_method_call(
            "xyz.openbmc_project.State.Host",
            "/xyz/openbmc_project/state/host0",
            "org.freedesktop.DBus.Properties",
            "GetAll"
        );

        getAllMethod.append("xyz.openbmc_project.State.Host");

        auto allReply = bus.call(getAllMethod);

        using PropertyMap = std::map<std::string,
            std::variant<std::string, int64_t, uint64_t, double, bool>>;
        PropertyMap properties;
        allReply.read(properties);

        for (const auto& [name, value] : properties)
        {
            std::cout << "  " << name << " = ";
            printVariant(value);
            std::cout << "\n";
        }
        std::cout << "\n";

        // ========================================
        // Example 3: Use Object Mapper
        // ========================================
        std::cout << "=== Finding Sensors via Object Mapper ===\n";

        auto mapperMethod = bus.new_method_call(
            "xyz.openbmc_project.ObjectMapper",
            "/xyz/openbmc_project/object_mapper",
            "xyz.openbmc_project.ObjectMapper",
            "GetSubTreePaths"
        );

        // Arguments: path, depth, interfaces
        mapperMethod.append("/xyz/openbmc_project/sensors");  // Root path
        mapperMethod.append(0);                                // Depth (0 = all)
        std::vector<std::string> interfaces = {
            "xyz.openbmc_project.Sensor.Value"
        };
        mapperMethod.append(interfaces);

        auto mapperReply = bus.call(mapperMethod);

        std::vector<std::string> sensorPaths;
        mapperReply.read(sensorPaths);

        std::cout << "Found " << sensorPaths.size() << " sensors:\n";
        for (size_t i = 0; i < std::min(sensorPaths.size(), size_t(5)); ++i)
        {
            std::cout << "  " << sensorPaths[i] << "\n";
        }
        if (sensorPaths.size() > 5)
        {
            std::cout << "  ... and " << (sensorPaths.size() - 5) << " more\n";
        }
        std::cout << "\n";

        // ========================================
        // Example 4: Read sensor value
        // ========================================
        if (!sensorPaths.empty())
        {
            std::cout << "=== Reading First Sensor Value ===\n";

            // First, find the service that owns this object
            auto getServiceMethod = bus.new_method_call(
                "xyz.openbmc_project.ObjectMapper",
                "/xyz/openbmc_project/object_mapper",
                "xyz.openbmc_project.ObjectMapper",
                "GetObject"
            );

            getServiceMethod.append(sensorPaths[0]);
            std::vector<std::string> empty;
            getServiceMethod.append(empty);

            auto serviceReply = bus.call(getServiceMethod);

            std::map<std::string, std::vector<std::string>> serviceMap;
            serviceReply.read(serviceMap);

            if (!serviceMap.empty())
            {
                std::string service = serviceMap.begin()->first;

                auto sensorMethod = bus.new_method_call(
                    service.c_str(),
                    sensorPaths[0].c_str(),
                    "org.freedesktop.DBus.Properties",
                    "Get"
                );

                sensorMethod.append("xyz.openbmc_project.Sensor.Value",
                                   "Value");

                auto sensorReply = bus.call(sensorMethod);

                std::variant<double> sensorValue;
                sensorReply.read(sensorValue);

                std::cout << "Sensor: " << sensorPaths[0] << "\n";
                std::cout << "Value: " << std::get<double>(sensorValue) << "\n";
            }
        }

        std::cout << "\nD-Bus client example completed successfully!\n";
    }
    catch (const sdbusplus::exception::exception& e)
    {
        std::cerr << "D-Bus error: " << e.what() << "\n";
        std::cerr << "Name: " << e.name() << "\n";
        std::cerr << "Description: " << e.description() << "\n";
        return 1;
    }

    return 0;
}
