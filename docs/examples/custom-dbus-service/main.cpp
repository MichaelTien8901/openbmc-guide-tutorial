/**
 * Custom D-Bus Service Example - Greeting Service
 *
 * Demonstrates how to create a complete D-Bus service for OpenBMC using
 * sdbusplus::asio with:
 *   - A read-write property (Name)
 *   - A method (Greet) that returns a greeting string
 *   - A signal (Greeted) emitted when someone is greeted
 *
 * This example uses the sdbusplus::asio::object_server API which is the
 * standard pattern for new OpenBMC services. The interface is defined in
 * xyz/openbmc_project/Example/Greeting.interface.yaml and code-generated
 * by sdbus++ at build time. However, this implementation uses the dynamic
 * (non-generated) API for simplicity and to show the underlying mechanics.
 *
 * Build with OpenBMC SDK:
 *   meson setup builddir && meson compile -C builddir
 *
 * Test:
 *   busctl call xyz.openbmc_project.Example.Greeting \
 *       /xyz/openbmc_project/example/greeting \
 *       xyz.openbmc_project.Example.Greeting Greet
 *
 * Source references:
 *   - sdbusplus asio: https://github.com/openbmc/sdbusplus
 *   - Object server: sdbusplus/asio/object_server.hpp
 *   - OpenBMC service patterns: https://github.com/openbmc/docs
 */

#include <boost/asio/io_context.hpp>
#include <boost/asio/signal_set.hpp>
#include <sdbusplus/asio/connection.hpp>
#include <sdbusplus/asio/object_server.hpp>
#include <sdbusplus/bus.hpp>
#include <sdbusplus/server.hpp>

#include <iostream>
#include <string>

// D-Bus identifiers
constexpr auto serviceName = "xyz.openbmc_project.Example.Greeting";
constexpr auto objectPath = "/xyz/openbmc_project/example/greeting";
constexpr auto interfaceName = "xyz.openbmc_project.Example.Greeting";

int main()
{
    // ========================================================================
    // 1. Create the Boost.Asio event loop
    // ========================================================================
    // All OpenBMC services use boost::asio::io_context as their main event
    // loop. This drives async I/O, timers, and D-Bus message dispatch.
    boost::asio::io_context io;

    // ========================================================================
    // 2. Connect to the system D-Bus
    // ========================================================================
    // sdbusplus::asio::connection wraps sd_bus and integrates with io_context
    // so that D-Bus messages are dispatched through the Boost.Asio event loop.
    auto conn = std::make_shared<sdbusplus::asio::connection>(io);

    // Request a well-known bus name. This is how other services and busctl
    // find us on D-Bus. The name must match the .service file BusName=.
    conn->request_name(serviceName);

    // ========================================================================
    // 3. Create the object server and interface
    // ========================================================================
    // The object_server manages D-Bus objects and their interfaces. It handles
    // introspection and the org.freedesktop.DBus.Properties interface.
    sdbusplus::asio::object_server server(conn);

    // Add our interface to the object path. This creates the D-Bus object
    // if it doesn't exist and attaches the interface to it.
    auto iface = server.add_interface(objectPath, interfaceName);

    // ========================================================================
    // 4. Register the Name property (read-write, string)
    // ========================================================================
    // The Name property holds the name to greet. Clients can read and write it
    // via the standard org.freedesktop.DBus.Properties interface. A
    // PropertiesChanged signal is emitted automatically on writes.
    std::string name = "World";

    iface->register_property(
        "Name", name,
        // Setter - called when a client writes the property via
        // org.freedesktop.DBus.Properties.Set or busctl set-property.
        [&name](const std::string& newValue, std::string& value) {
            if (newValue.empty())
            {
                std::cerr << "Rejected empty Name\n";
                return false; // Reject: empty name not allowed
            }
            std::cout << "Name changed: \"" << value << "\" -> \"" << newValue
                      << "\"\n";
            value = newValue;
            name = newValue;
            return true; // Accept the change
        },
        // Getter - called when a client reads the property.
        [&name](const std::string& /*storedValue*/) { return name; });

    // ========================================================================
    // 5. Register the Greet method
    // ========================================================================
    // The Greet method takes no arguments and returns a greeting string.
    // It also emits the Greeted signal with the greeting message.
    iface->register_method("Greet", [&name, &iface]() {
        std::string greeting = "Hello, " + name + "!";
        std::cout << "Greet called: " << greeting << "\n";

        // Emit the Greeted signal so that listeners are notified.
        // The signal carries the greeting string as defined in the YAML.
        sdbusplus::message_t msg =
            iface->new_signal("Greeted");
        msg.append(greeting);
        msg.signal_send();

        return greeting;
    });

    // ========================================================================
    // 6. Initialize the interface (make it visible on D-Bus)
    // ========================================================================
    // IMPORTANT: initialize() must be called after all properties, methods,
    // and signals are registered. This finalizes the vtable and makes the
    // interface visible to other D-Bus clients.
    iface->initialize();

    // ========================================================================
    // 7. Handle SIGINT/SIGTERM for clean shutdown
    // ========================================================================
    // OpenBMC services should handle signals gracefully. systemd sends
    // SIGTERM when stopping the service.
    boost::asio::signal_set signals(io, SIGINT, SIGTERM);
    signals.async_wait(
        [&io](const boost::system::error_code& ec, int signo) {
            if (!ec)
            {
                std::cout << "\nReceived signal " << signo
                          << ", shutting down\n";
                io.stop();
            }
        });

    // ========================================================================
    // 8. Log startup info
    // ========================================================================
    std::cout << "example-greeting service started\n";
    std::cout << "  Service:   " << serviceName << "\n";
    std::cout << "  Object:    " << objectPath << "\n";
    std::cout << "  Interface: " << interfaceName << "\n";
    std::cout << "\nTest with:\n";
    std::cout << "  busctl introspect " << serviceName << " " << objectPath
              << "\n";
    std::cout << "  busctl call " << serviceName << " " << objectPath << " "
              << interfaceName << " Greet\n";
    std::cout << "  busctl set-property " << serviceName << " " << objectPath
              << " " << interfaceName << " Name s \"Alice\"\n";

    // ========================================================================
    // 9. Run the event loop
    // ========================================================================
    // This blocks until io.stop() is called (from signal handler) or all
    // async work is complete. The event loop dispatches D-Bus messages,
    // timers, and I/O.
    io.run();

    std::cout << "example-greeting service stopped\n";
    return 0;
}
