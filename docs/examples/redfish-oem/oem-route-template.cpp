/**
 * OEM Redfish Route Handler Template
 *
 * Skeleton implementation of a custom OEM Redfish resource for bmcweb.
 * Search for "TODO" to find all customization points.
 *
 * Integration steps:
 *   1. Copy this file to <bmcweb>/redfish-core/lib/oem_yourvendor.hpp
 *   2. Replace all TODO placeholders with vendor-specific values
 *   3. Register routes in src/webserver_main.cpp (see bottom of file)
 *   4. Create a Yocto bbappend patch and rebuild bmcweb
 *
 * Source reference:
 *   - Route patterns: https://github.com/openbmc/bmcweb/blob/master/redfish-core/lib/managers.hpp
 *   - Privilege registry: https://github.com/openbmc/bmcweb/blob/master/redfish-core/include/registries/privilege_registry.hpp
 *   - AsyncResp pattern: https://github.com/openbmc/bmcweb/blob/master/http/utility.hpp
 */

#pragma once

#include "app.hpp"
#include "dbus_utility.hpp"
#include "query.hpp"
#include "registries/privilege_registry.hpp"
#include "utils/dbus_utils.hpp"

#include <nlohmann/json.hpp>
#include <sdbusplus/asio/property.hpp>

namespace redfish
{

// TODO: Replace "YourVendor" with your vendor name (e.g., "Acme", "Contoso")
constexpr const char* oemVendorName = "YourVendor";

// TODO: Replace with your OEM @odata.type namespace
constexpr const char* oemOdataTypeRoot =
    "#OemYourVendor.v1_0_0.OemServiceRoot";
constexpr const char* oemOdataTypeHealth =
    "#OemYourVendorHealth.v1_0_0.HealthSummary";

// ---------------------------------------------------------------------------
// OEM Root Resource
// GET /redfish/v1/Oem/YourVendor/
// ---------------------------------------------------------------------------

inline void requestRoutesOemRoot(App& app)
{
    BMCWEB_ROUTE(app, "/redfish/v1/Oem/<str>/")
        .privileges(redfish::privileges::getManager)
        .methods(boost::beast::http::verb::get)(
            [](const crow::Request&,
               const std::shared_ptr<bmcweb::AsyncResp>& asyncResp,
               const std::string& vendorName) {
                // Validate vendor name segment
                if (vendorName != oemVendorName)
                {
                    messages::resourceNotFound(asyncResp->res, "OemRoot",
                                               vendorName);
                    return;
                }

                asyncResp->res.jsonValue["@odata.type"] = oemOdataTypeRoot;
                asyncResp->res.jsonValue["@odata.id"] =
                    std::string("/redfish/v1/Oem/") + oemVendorName;
                asyncResp->res.jsonValue["Id"] = oemVendorName;
                asyncResp->res.jsonValue["Name"] =
                    std::string(oemVendorName) + " OEM Extensions";

                // TODO: Add a Description for your OEM root
                asyncResp->res.jsonValue["Description"] =
                    "Custom OEM resources";

                // TODO: Add links to your OEM sub-resources here.
                // Each sub-resource needs its own route handler below.
                asyncResp->res.jsonValue["Health"]["@odata.id"] =
                    std::string("/redfish/v1/Oem/") + oemVendorName +
                    "/Health";

                // TODO: Add more sub-resource links as needed, for example:
                // asyncResp->res.jsonValue["Inventory"]["@odata.id"] =
                //     std::string("/redfish/v1/Oem/") + oemVendorName +
                //     "/Inventory";
            });
}

// ---------------------------------------------------------------------------
// OEM Health Summary Resource
// GET /redfish/v1/Oem/YourVendor/Health
//
// TODO: Replace this with your actual OEM resource. This is a minimal
// example that demonstrates the route handler pattern, D-Bus property
// reads, and JSON response construction.
// ---------------------------------------------------------------------------

inline void requestRoutesOemHealth(App& app)
{
    BMCWEB_ROUTE(app, "/redfish/v1/Oem/<str>/Health")
        .privileges(redfish::privileges::getManager)
        .methods(boost::beast::http::verb::get)(
            [](const crow::Request&,
               const std::shared_ptr<bmcweb::AsyncResp>& asyncResp,
               const std::string& vendorName) {
                if (vendorName != oemVendorName)
                {
                    messages::resourceNotFound(asyncResp->res, "Health",
                                               vendorName);
                    return;
                }

                // Standard Redfish metadata fields
                asyncResp->res.jsonValue["@odata.type"] = oemOdataTypeHealth;
                asyncResp->res.jsonValue["@odata.id"] =
                    std::string("/redfish/v1/Oem/") + oemVendorName +
                    "/Health";
                asyncResp->res.jsonValue["Id"] = "Health";
                asyncResp->res.jsonValue["Name"] = "System Health Summary";

                // TODO: Replace static values with D-Bus property reads.
                // The example below shows both patterns: static and async.

                // --- Static properties (replace with real data) ---
                asyncResp->res.jsonValue["OverallHealth"] = "OK";
                asyncResp->res.jsonValue["LastCheckTime"] =
                    "2024-01-01T00:00:00Z";

                // TODO: Add your custom properties here, for example:
                // asyncResp->res.jsonValue["FanHealth"] = "OK";
                // asyncResp->res.jsonValue["PowerHealth"] = "OK";
                // asyncResp->res.jsonValue["ThermalHealth"] = "OK";

                // --- Async D-Bus property read example ---
                // TODO: Replace service name, object path, interface, and
                // property with values for your platform.
                //
                // sdbusplus::asio::getProperty<std::string>(
                //     *crow::connections::systemBus,
                //     "xyz.openbmc_project.State.BMC",           // D-Bus service
                //     "/xyz/openbmc_project/state/bmc0",         // Object path
                //     "xyz.openbmc_project.State.BMC",           // Interface
                //     "CurrentBMCState",                         // Property
                //     [asyncResp](const boost::system::error_code& ec,
                //                 const std::string& value) {
                //         if (ec)
                //         {
                //             asyncResp->res.jsonValue["BmcState"] = "Unknown";
                //             return;
                //         }
                //         asyncResp->res.jsonValue["BmcState"] = value;
                //     });

                // Status block (follows Redfish Resource.Status pattern)
                asyncResp->res.jsonValue["Status"]["State"] = "Enabled";
                asyncResp->res.jsonValue["Status"]["Health"] = "OK";
            });
}

// ---------------------------------------------------------------------------
// TODO: Add more route handlers for additional OEM resources here.
//
// Follow the same pattern:
//   1. Define an inline void requestRoutesYourResource(App& app) function
//   2. Use BMCWEB_ROUTE with /redfish/v1/Oem/<str>/YourResource
//   3. Validate vendorName != oemVendorName
//   4. Populate asyncResp->res.jsonValue with response data
//   5. Register the function in requestRoutesYourVendorOem() below
//
// For POST actions, see the RunTest example in ../redfish/oem_resource.hpp
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// Route Registration
//
// This function is called once at bmcweb startup. Add it to
// src/webserver_main.cpp:
//
//   #include "redfish-core/lib/oem_yourvendor.hpp"
//   ...
//   redfish::requestRoutesYourVendorOem(app);
// ---------------------------------------------------------------------------

// TODO: Rename this function to match your vendor name
inline void requestRoutesYourVendorOem(App& app)
{
    requestRoutesOemRoot(app);
    requestRoutesOemHealth(app);
    // TODO: Register additional route handlers here
}

} // namespace redfish
