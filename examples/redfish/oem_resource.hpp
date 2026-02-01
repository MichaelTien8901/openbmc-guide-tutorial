/**
 * OEM Redfish Resource Handler
 *
 * Example implementation of custom OEM Redfish resources for bmcweb.
 *
 * Source Reference:
 *   - Based on patterns from: https://github.com/openbmc/bmcweb
 *   - Route examples: https://github.com/openbmc/bmcweb/blob/master/redfish-core/lib/managers.hpp
 *   - Privilege registry: https://github.com/openbmc/bmcweb/blob/master/redfish-core/include/registries/privilege_registry.hpp
 *
 * To integrate:
 * 1. Copy this file to <bmcweb>/redfish-core/lib/
 * 2. Include and register routes in appropriate location
 * 3. Rebuild bmcweb
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

// Replace "MyVendor" with your vendor name
constexpr const char* oemVendorName = "MyVendor";

/**
 * OEM Root Resource
 * GET /redfish/v1/Oem/MyVendor/
 */
inline void requestRoutesOemRoot(App& app)
{
    BMCWEB_ROUTE(app, "/redfish/v1/Oem/<str>/")
        .privileges(redfish::privileges::getManager)
        .methods(boost::beast::http::verb::get)(
            [](const crow::Request&,
               const std::shared_ptr<bmcweb::AsyncResp>& asyncResp,
               const std::string& vendorName) {
                if (vendorName != oemVendorName)
                {
                    messages::resourceNotFound(asyncResp->res, "OemRoot",
                                               vendorName);
                    return;
                }

                asyncResp->res.jsonValue["@odata.type"] =
                    "#OemServiceRoot.v1_0_0.OemServiceRoot";
                asyncResp->res.jsonValue["@odata.id"] =
                    "/redfish/v1/Oem/MyVendor";
                asyncResp->res.jsonValue["Id"] = "MyVendor";
                asyncResp->res.jsonValue["Name"] = "MyVendor OEM Extensions";
                asyncResp->res.jsonValue["Description"] =
                    "Custom OEM resources for MyVendor";

                // Links to OEM resources
                asyncResp->res.jsonValue["BoardInfo"]["@odata.id"] =
                    "/redfish/v1/Oem/MyVendor/BoardInfo";
                asyncResp->res.jsonValue["DiagnosticService"]["@odata.id"] =
                    "/redfish/v1/Oem/MyVendor/DiagnosticService";
            });
}

/**
 * Board Info Resource
 * GET /redfish/v1/Oem/MyVendor/BoardInfo
 */
inline void requestRoutesBoardInfo(App& app)
{
    BMCWEB_ROUTE(app, "/redfish/v1/Oem/<str>/BoardInfo")
        .privileges(redfish::privileges::getManager)
        .methods(boost::beast::http::verb::get)(
            [](const crow::Request&,
               const std::shared_ptr<bmcweb::AsyncResp>& asyncResp,
               const std::string& vendorName) {
                if (vendorName != oemVendorName)
                {
                    messages::resourceNotFound(asyncResp->res, "BoardInfo",
                                               vendorName);
                    return;
                }

                asyncResp->res.jsonValue["@odata.type"] =
                    "#OemBoardInfo.v1_0_0.BoardInfo";
                asyncResp->res.jsonValue["@odata.id"] =
                    "/redfish/v1/Oem/MyVendor/BoardInfo";
                asyncResp->res.jsonValue["Id"] = "BoardInfo";
                asyncResp->res.jsonValue["Name"] = "Board Information";

                // Populate from D-Bus
                // Example: Read from inventory service
                sdbusplus::asio::getProperty<std::string>(
                    *crow::connections::systemBus,
                    "xyz.openbmc_project.Inventory.Manager",
                    "/xyz/openbmc_project/inventory/system/board",
                    "xyz.openbmc_project.Inventory.Decorator.Asset",
                    "Manufacturer",
                    [asyncResp](const boost::system::error_code& ec,
                                const std::string& manufacturer) {
                        if (ec)
                        {
                            // Use defaults if not available
                            asyncResp->res.jsonValue["Manufacturer"] =
                                "Unknown";
                            return;
                        }
                        asyncResp->res.jsonValue["Manufacturer"] = manufacturer;
                    });

                // Static board info (in production, read from hardware)
                asyncResp->res.jsonValue["BoardType"] = "Server";
                asyncResp->res.jsonValue["BoardRevision"] = "Rev B";
                asyncResp->res.jsonValue["CpuSlots"] = 2;
                asyncResp->res.jsonValue["DimmSlots"] = 16;
                asyncResp->res.jsonValue["PcieSlots"] = 4;
                asyncResp->res.jsonValue["MaxPowerWatts"] = 1000;

                // Status
                asyncResp->res.jsonValue["Status"]["State"] = "Enabled";
                asyncResp->res.jsonValue["Status"]["Health"] = "OK";
            });
}

/**
 * Diagnostic Service Resource
 * GET /redfish/v1/Oem/MyVendor/DiagnosticService
 */
inline void requestRoutesDiagnosticService(App& app)
{
    BMCWEB_ROUTE(app, "/redfish/v1/Oem/<str>/DiagnosticService")
        .privileges(redfish::privileges::getManager)
        .methods(boost::beast::http::verb::get)(
            [](const crow::Request&,
               const std::shared_ptr<bmcweb::AsyncResp>& asyncResp,
               const std::string& vendorName) {
                if (vendorName != oemVendorName)
                {
                    messages::resourceNotFound(asyncResp->res,
                                               "DiagnosticService", vendorName);
                    return;
                }

                asyncResp->res.jsonValue["@odata.type"] =
                    "#OemDiagnosticService.v1_0_0.DiagnosticService";
                asyncResp->res.jsonValue["@odata.id"] =
                    "/redfish/v1/Oem/MyVendor/DiagnosticService";
                asyncResp->res.jsonValue["Id"] = "DiagnosticService";
                asyncResp->res.jsonValue["Name"] = "Diagnostic Service";
                asyncResp->res.jsonValue["Description"] =
                    "Service for running diagnostic tests";

                // Available tests
                nlohmann::json& tests =
                    asyncResp->res.jsonValue["AvailableTests"];
                tests = nlohmann::json::array();
                tests.push_back({{"Id", 1},
                                 {"Name", "Memory Test"},
                                 {"Description", "Basic memory test"}});
                tests.push_back({{"Id", 2},
                                 {"Name", "Network Test"},
                                 {"Description", "Network connectivity test"}});
                tests.push_back({{"Id", 3},
                                 {"Name", "Storage Test"},
                                 {"Description", "Storage health check"}});

                // Actions
                nlohmann::json& actions = asyncResp->res.jsonValue["Actions"];
                actions["#DiagnosticService.RunTest"]["target"] =
                    "/redfish/v1/Oem/MyVendor/DiagnosticService/Actions/"
                    "DiagnosticService.RunTest";
                actions["#DiagnosticService.RunTest"]
                       ["@Redfish.ActionInfo"] =
                           "/redfish/v1/Oem/MyVendor/DiagnosticService/"
                           "RunTestActionInfo";

                // Status
                asyncResp->res.jsonValue["ServiceEnabled"] = true;
            });
}

/**
 * Run Test Action
 * POST /redfish/v1/Oem/MyVendor/DiagnosticService/Actions/DiagnosticService.RunTest
 */
inline void requestRoutesRunTest(App& app)
{
    BMCWEB_ROUTE(
        app,
        "/redfish/v1/Oem/<str>/DiagnosticService/Actions/DiagnosticService.RunTest")
        .privileges(redfish::privileges::postManager)
        .methods(boost::beast::http::verb::post)(
            [](const crow::Request& req,
               const std::shared_ptr<bmcweb::AsyncResp>& asyncResp,
               const std::string& vendorName) {
                if (vendorName != oemVendorName)
                {
                    messages::resourceNotFound(asyncResp->res, "Action",
                                               "RunTest");
                    return;
                }

                // Parse request body
                std::optional<uint32_t> testId;
                if (!json_util::readJsonAction(req, asyncResp->res, "TestId",
                                               testId))
                {
                    return;
                }

                if (!testId)
                {
                    messages::actionParameterMissing(
                        asyncResp->res, "DiagnosticService.RunTest", "TestId");
                    return;
                }

                // Validate test ID
                if (*testId < 1 || *testId > 3)
                {
                    messages::actionParameterValueError(
                        asyncResp->res, std::to_string(*testId), "TestId",
                        "DiagnosticService.RunTest");
                    return;
                }

                BMCWEB_LOG_INFO("Running diagnostic test: {}", *testId);

                // In production, trigger actual diagnostic
                // For example, call a D-Bus method:
                // crow::connections::systemBus->async_method_call(...)

                // Return success with task
                asyncResp->res.result(
                    boost::beast::http::status::accepted);
                asyncResp->res.jsonValue["@odata.type"] =
                    "#Task.v1_0_0.Task";
                asyncResp->res.jsonValue["Id"] = "DiagTask1";
                asyncResp->res.jsonValue["Name"] = "Diagnostic Test";
                asyncResp->res.jsonValue["TaskState"] = "Running";
                asyncResp->res.jsonValue["StartTime"] =
                    "2024-01-01T12:00:00Z";
            });
}

/**
 * Register all OEM routes
 */
inline void requestRoutesMyVendorOem(App& app)
{
    requestRoutesOemRoot(app);
    requestRoutesBoardInfo(app);
    requestRoutesDiagnosticService(app);
    requestRoutesRunTest(app);
}

} // namespace redfish
