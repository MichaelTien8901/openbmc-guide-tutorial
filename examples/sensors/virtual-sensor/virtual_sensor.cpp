/**
 * Virtual Sensor Example
 *
 * Demonstrates creating a virtual sensor that calculates total system power
 * by reading PSU power values and summing them.
 *
 * Source Reference:
 *   - virtual-sensor: https://github.com/openbmc/phosphor-virtual-sensor
 *   - dbus-sensors: https://github.com/openbmc/dbus-sensors
 *   - Sensor interfaces: https://github.com/openbmc/phosphor-dbus-interfaces/blob/master/yaml/xyz/openbmc_project/Sensor/Value.interface.yaml
 *
 * Build with SDK:
 *   $CXX -std=c++20 virtual_sensor.cpp -o virtual_sensor \
 *       $(pkg-config --cflags --libs sdbusplus)
 */

#include <sdbusplus/bus.hpp>
#include <sdbusplus/asio/connection.hpp>
#include <sdbusplus/asio/object_server.hpp>
#include <boost/asio.hpp>
#include <iostream>
#include <vector>
#include <string>
#include <chrono>

// Configuration
constexpr auto serviceName = "xyz.openbmc_project.VirtualSensor.TotalPower";
constexpr auto objectPath = "/xyz/openbmc_project/sensors/power/Total_Power";
constexpr auto sensorInterface = "xyz.openbmc_project.Sensor.Value";

// PSU sensor paths to aggregate
const std::vector<std::string> psuSensorPaths = {
    "/xyz/openbmc_project/sensors/power/PSU0_Output_Power",
    "/xyz/openbmc_project/sensors/power/PSU1_Output_Power"
};

class VirtualSensor
{
  public:
    VirtualSensor(boost::asio::io_context& io,
                  std::shared_ptr<sdbusplus::asio::connection> conn) :
        io_(io),
        conn_(conn), timer_(io), value_(0.0), minValue_(0.0), maxValue_(10000.0)
    {
        // Create object server
        server_ = std::make_unique<sdbusplus::asio::object_server>(conn_);

        // Add sensor interface
        iface_ = server_->add_interface(objectPath, sensorInterface);

        // Register Value property (read-only)
        iface_->register_property_r(
            "Value", value_, sdbusplus::vtable::property_::emits_change,
            [this](const double&) { return value_; });

        // Register Unit property
        std::string unit = "xyz.openbmc_project.Sensor.Value.Unit.Watts";
        iface_->register_property_r(
            "Unit", unit, sdbusplus::vtable::property_::const_,
            [unit](const std::string&) { return unit; });

        // Register MinValue property
        iface_->register_property_r(
            "MinValue", minValue_, sdbusplus::vtable::property_::const_,
            [this](const double&) { return minValue_; });

        // Register MaxValue property
        iface_->register_property_r(
            "MaxValue", maxValue_, sdbusplus::vtable::property_::const_,
            [this](const double&) { return maxValue_; });

        iface_->initialize();

        std::cout << "Virtual sensor created at: " << objectPath << "\n";

        // Start periodic update
        startUpdate();
    }

  private:
    void startUpdate()
    {
        timer_.expires_after(std::chrono::seconds(1));
        timer_.async_wait([this](const boost::system::error_code& ec) {
            if (!ec)
            {
                updateValue();
                startUpdate();
            }
        });
    }

    void updateValue()
    {
        double totalPower = 0.0;
        bool anyValid = false;

        for (const auto& path : psuSensorPaths)
        {
            try
            {
                auto method = conn_->new_method_call(
                    "xyz.openbmc_project.PSUSensor", path.c_str(),
                    "org.freedesktop.DBus.Properties", "Get");
                method.append(sensorInterface, "Value");

                auto reply = conn_->call(method);
                std::variant<double> value;
                reply.read(value);

                double psuPower = std::get<double>(value);
                if (!std::isnan(psuPower))
                {
                    totalPower += psuPower;
                    anyValid = true;
                }
            }
            catch (const std::exception& e)
            {
                // PSU sensor not available, skip
            }
        }

        if (anyValid)
        {
            value_ = totalPower;
            iface_->signal_property("Value");
            std::cout << "Total Power: " << value_ << " W\n";
        }
    }

    boost::asio::io_context& io_;
    std::shared_ptr<sdbusplus::asio::connection> conn_;
    std::unique_ptr<sdbusplus::asio::object_server> server_;
    std::shared_ptr<sdbusplus::asio::dbus_interface> iface_;
    boost::asio::steady_timer timer_;

    double value_;
    double minValue_;
    double maxValue_;
};

int main()
{
    boost::asio::io_context io;
    auto conn = std::make_shared<sdbusplus::asio::connection>(io);

    // Request service name
    conn->request_name(serviceName);
    std::cout << "Service: " << serviceName << "\n";

    // Create virtual sensor
    VirtualSensor sensor(io, conn);

    std::cout << "\nVirtual sensor running. Test with:\n";
    std::cout << "  busctl get-property " << serviceName << " " << objectPath
              << " " << sensorInterface << " Value\n";
    std::cout << "\nPress Ctrl+C to exit.\n";

    io.run();
    return 0;
}
