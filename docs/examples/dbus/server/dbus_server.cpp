/**
 * D-Bus Server Example
 *
 * Demonstrates how to:
 * - Create a D-Bus service
 * - Expose properties
 * - Handle property changes
 * - Emit signals
 *
 * Source Reference:
 *   - sdbusplus library: https://github.com/openbmc/sdbusplus
 *   - ASIO integration: https://github.com/openbmc/sdbusplus/blob/master/include/sdbusplus/asio/object_server.hpp
 *   - Examples: https://github.com/openbmc/sdbusplus/tree/master/example
 *
 * Build with SDK:
 *   $CXX -std=c++20 dbus_server.cpp -o dbus_server \
 *       $(pkg-config --cflags --libs sdbusplus)
 */

#include <sdbusplus/bus.hpp>
#include <sdbusplus/server.hpp>
#include <sdbusplus/asio/connection.hpp>
#include <sdbusplus/asio/object_server.hpp>
#include <boost/asio.hpp>
#include <iostream>
#include <string>

// Service configuration
constexpr auto serviceName = "xyz.openbmc_project.Example.Server";
constexpr auto objectPath = "/xyz/openbmc_project/example/server";
constexpr auto interfaceName = "xyz.openbmc_project.Example.Counter";

int main()
{
    // Create IO context for async operations
    boost::asio::io_context io;

    // Connect to system bus
    auto conn = std::make_shared<sdbusplus::asio::connection>(io);

    // Request well-known name
    conn->request_name(serviceName);
    std::cout << "Registered service: " << serviceName << "\n";

    // Create object server
    sdbusplus::asio::object_server server(conn);

    // Add interface to object
    auto iface = server.add_interface(objectPath, interfaceName);

    // ========================================
    // Property: Counter (read-write)
    // ========================================
    int64_t counter = 0;

    iface->register_property(
        "Counter", counter,
        // Setter with validation
        [&counter](const int64_t& newValue, int64_t& value) {
            if (newValue < 0)
            {
                std::cerr << "Rejected negative value: " << newValue << "\n";
                return false;  // Reject the change
            }
            std::cout << "Counter changed: " << value << " -> " << newValue << "\n";
            value = newValue;
            counter = newValue;
            return true;  // Accept the change
        },
        // Getter
        [&counter](const int64_t& value) {
            return counter;
        }
    );

    // ========================================
    // Property: Name (read-only)
    // ========================================
    std::string name = "Example Server";

    iface->register_property_r(
        "Name", name,
        sdbusplus::vtable::property_::const_,
        [&name](const std::string&) {
            return name;
        }
    );

    // ========================================
    // Property: Running (read-only)
    // ========================================
    bool running = true;

    iface->register_property_r(
        "Running", running,
        sdbusplus::vtable::property_::const_,
        [&running](const bool&) {
            return running;
        }
    );

    // ========================================
    // Method: Increment
    // ========================================
    iface->register_method("Increment", [&counter, &iface]() {
        counter++;
        std::cout << "Increment called, counter = " << counter << "\n";

        // Emit PropertiesChanged signal
        iface->signal_property("Counter");

        return counter;
    });

    // ========================================
    // Method: Reset
    // ========================================
    iface->register_method("Reset", [&counter, &iface]() {
        int64_t oldValue = counter;
        counter = 0;
        std::cout << "Reset called, counter reset from " << oldValue << " to 0\n";

        iface->signal_property("Counter");
    });

    // ========================================
    // Method: Add (with parameter)
    // ========================================
    iface->register_method("Add", [&counter, &iface](int64_t amount) {
        counter += amount;
        std::cout << "Add(" << amount << ") called, counter = " << counter << "\n";

        iface->signal_property("Counter");

        return counter;
    });

    // Initialize the interface (make it visible on D-Bus)
    iface->initialize();

    std::cout << "Object path: " << objectPath << "\n";
    std::cout << "Interface: " << interfaceName << "\n";
    std::cout << "\nServer running. Test with:\n";
    std::cout << "  busctl introspect " << serviceName << " " << objectPath << "\n";
    std::cout << "  busctl get-property " << serviceName << " " << objectPath
              << " " << interfaceName << " Counter\n";
    std::cout << "  busctl call " << serviceName << " " << objectPath
              << " " << interfaceName << " Increment\n";
    std::cout << "  busctl set-property " << serviceName << " " << objectPath
              << " " << interfaceName << " Counter x 42\n";
    std::cout << "\nPress Ctrl+C to exit.\n";

    // Run the event loop
    io.run();

    return 0;
}
