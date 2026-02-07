---
layout: default
title: Redfish Events & Telemetry
parent: Interfaces
nav_order: 8
difficulty: intermediate
prerequisites:
  - redfish-guide
  - environment-setup
last_modified_date: 2026-02-06
---

# Redfish Events & Telemetry
{: .no_toc }

Subscribe to asynchronous Redfish events and collect periodic telemetry metric reports from OpenBMC.
{: .fs-6 .fw-300 }

## Table of Contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

## Overview

The Redfish **EventService** and **TelemetryService** allow management clients to receive real-time notifications and collect periodic sensor data without polling. OpenBMC implements both services through **bmcweb**, translating D-Bus signals into standards-compliant Redfish events and metric reports.

The EventService supports two delivery mechanisms: **push-style subscriptions** (HTTP POST callbacks) and **Server-Sent Events (SSE)** streaming. Push subscriptions send event payloads to a client-supplied destination URL, while SSE keeps a persistent HTTP connection open for continuous event delivery. The TelemetryService complements events by collecting sensor readings at defined intervals and storing them as retrievable metric reports.

**Key concepts covered:**
- Creating, listing, and deleting EventService push subscriptions
- Opening and filtering SSE event streams
- Defining and retrieving TelemetryService metric reports
- Subscription lifecycle management (limits, expiration, retry)

---

## Architecture

```
+-----------------------------------------------------------------------+
|                  Redfish Events & Telemetry Architecture              |
+-----------------------------------------------------------------------+
|                                                                       |
|  +-------------------------------+                                    |
|  |     Management Client(s)      |                                    |
|  |  (scripts, dashboards, SIEM)  |                                    |
|  +-------------------------------+                                    |
|        |                  ^                                           |
|  SSE stream /        POST callback                                    |
|  GET request         (push events)                                    |
|        |                  |                                           |
|        v                  |                                           |
|  +------------------------------------------------------------+       |
|  |                        bmcweb                              |       |
|  |                                                            |       |
|  |  +------------------+  +------------------+                |       |
|  |  | EventService     |  | TelemetryService |                |       |
|  |  | - Subscriptions  |  | - MetricReport   |                |       |
|  |  | - SSE handler    |  |   Definitions    |                |       |
|  |  | - Push dispatch  |  | - MetricReports  |                |       |
|  |  +--------+---------+  +--------+---------+                |       |
|  |           |                     |                          |       |
|  +------------------------------------------------------------+       |
|              |                     |                                  |
|              v                     v                                  |
|  +------------------------------------------------------------+       |
|  |                         D-Bus                              |       |
|  |  phosphor-dbus-interfaces (Sensor.Value, Logging, etc.)    |       |
|  |  dbus-sensors, phosphor-logging, phosphor-health-monitor   |       |
|  +------------------------------------------------------------+       |
|                                                                       |
+-----------------------------------------------------------------------+
```

### How Events Flow

1. A D-Bus signal fires (sensor threshold crossed, log entry created, inventory changed).
2. bmcweb's event handler matches the signal against active subscription filters.
3. For **push subscriptions**, bmcweb sends an HTTP POST to the subscriber's `Destination` URL.
4. For **SSE connections**, bmcweb writes the event to every open SSE stream that matches the filter.

### How Telemetry Works

1. A `MetricReportDefinition` tells bmcweb which sensor properties to collect and how often.
2. The underlying `dbus-sensors` or `phosphor-virtual-sensor` services expose readings on D-Bus.
3. bmcweb (backed by `phosphor-health-monitor` or the telemetry daemon) samples those readings and stores a `MetricReport`.
4. Clients retrieve the report on demand or receive it as a `MetricReport` event through an active subscription.

---

## Configuration

### Build-Time Configuration (Yocto)

Enable event and telemetry features in your bmcweb build:

```bitbake
# In your machine .conf or local.conf
EXTRA_OEMESON:pn-bmcweb = " \
    -Dredfish=enabled \
    -Dinsecure-push-style-notification=enabled \
    -Dredfish-dbus-log=enabled \
"
```

{: .warning }
> The `insecure-push-style-notification` option enables push-style event delivery without requiring TLS verification of the subscriber destination. In production, use proper certificate validation. This flag is useful for QEMU development and testing.

### Meson Build Options for Events & Telemetry

| Option | Default | Description |
|--------|---------|-------------|
| `insecure-push-style-notification` | disabled | Push event POST to subscriber destinations |
| `redfish-dbus-log` | enabled | Map D-Bus log signals to Redfish events |
| `redfish-bmc-journal` | enabled | Expose BMC journal entries as log events |

### Runtime Configuration

```bash
# Check bmcweb status
systemctl status bmcweb

# Verify EventService is available
curl -k -u root:0penBmc \
    https://localhost/redfish/v1/EventService

# Verify TelemetryService is available
curl -k -u root:0penBmc \
    https://localhost/redfish/v1/TelemetryService
```

### Configure EventService Parameters

```bash
# View current settings
curl -k -u root:0penBmc \
    https://localhost/redfish/v1/EventService | jq

# Tune delivery retry behavior
curl -k -u root:0penBmc -X PATCH \
    -H "Content-Type: application/json" \
    -d '{
        "ServiceEnabled": true,
        "DeliveryRetryAttempts": 3,
        "DeliveryRetryIntervalSeconds": 60
    }' \
    https://localhost/redfish/v1/EventService
```

{: .note }
> The `DeliveryRetryAttempts` and `DeliveryRetryIntervalSeconds` values apply to push-style subscriptions only. SSE streams reconnect at the client's discretion.

---

## EventService Push Subscriptions

Push subscriptions instruct bmcweb to HTTP POST event payloads to a URL you specify. This is the standard Redfish event delivery model.

### Create a Push Subscription

```bash
# Set up alias for convenience
alias bmcurl='curl -k -u root:0penBmc'

# Create a subscription that receives Alert and ResourceUpdated events
bmcurl -X POST \
    -H "Content-Type: application/json" \
    -d '{
        "Destination": "https://my-monitoring-server:8443/redfish-events",
        "Protocol": "Redfish",
        "EventFormatType": "Event",
        "RegistryPrefixes": ["OpenBMC"],
        "ResourceTypes": ["Chassis", "Systems"],
        "Context": "my-bmc-01-alerts"
    }' \
    https://localhost/redfish/v1/EventService/Subscriptions
```

The response includes a `Location` header with the new subscription URI, for example `/redfish/v1/EventService/Subscriptions/1`.

### Subscription Properties

| Property | Type | Description |
|----------|------|-------------|
| `Destination` | string (URI) | URL that receives HTTP POST event payloads |
| `Protocol` | string | Must be `"Redfish"` |
| `EventFormatType` | string | `"Event"` (default) or `"MetricReport"` |
| `RegistryPrefixes` | array | Filter by message registry prefix (e.g., `["OpenBMC", "TaskEvent"]`) |
| `ResourceTypes` | array | Filter by resource type (e.g., `["Chassis", "Systems"]`) |
| `Context` | string | Opaque string echoed in every event payload for client correlation |
| `HttpHeaders` | array | Custom HTTP headers sent with each POST (e.g., auth tokens) |

### List All Subscriptions

```bash
bmcurl https://localhost/redfish/v1/EventService/Subscriptions | jq
```

### Get a Specific Subscription

```bash
bmcurl https://localhost/redfish/v1/EventService/Subscriptions/1 | jq
```

### Delete a Subscription

```bash
bmcurl -X DELETE \
    https://localhost/redfish/v1/EventService/Subscriptions/1
```

### Push Event Payload Format

When an event fires, bmcweb POSTs a JSON body to the subscription destination:

```json
{
    "@odata.type": "#Event.v1_4_0.Event",
    "Id": "1",
    "Name": "Event Array",
    "Context": "my-bmc-01-alerts",
    "Events": [
        {
            "EventType": "Alert",
            "Severity": "Warning",
            "Message": "Temperature threshold exceeded on CPU_Temp.",
            "MessageId": "OpenBMC.0.1.SensorThresholdWarning",
            "MessageArgs": ["CPU_Temp", "85", "80"],
            "OriginOfCondition": {
                "@odata.id": "/redfish/v1/Chassis/chassis/Sensors/CPU_Temp"
            },
            "EventTimestamp": "2026-02-06T14:30:00Z"
        }
    ]
}
```

{: .tip }
> Use `RegistryPrefixes` and `ResourceTypes` filters to reduce noise. A subscription with no filters receives all events, which can overwhelm the destination under heavy load.

---

## Server-Sent Events (SSE) Streaming

SSE provides a persistent, one-way HTTP stream from bmcweb to the client. It is useful for real-time dashboards, monitoring scripts, and situations where the client cannot expose an inbound HTTP endpoint.

### Open an SSE Connection

```bash
# Open SSE stream (runs until you press Ctrl+C)
curl -k -u root:0penBmc -N \
    -H "Accept: text/event-stream" \
    https://localhost/redfish/v1/EventService/SSE
```

The `-N` flag disables output buffering so events appear immediately.

### SSE Event Format

Each event arrives as a `text/event-stream` message:

```
id: 1
data: {"@odata.type":"#Event.v1_4_0.Event","Id":"1","Name":"Event Array","Events":[{"EventType":"Alert","MessageId":"OpenBMC.0.1.SensorThresholdWarning","Message":"Temperature threshold exceeded on CPU_Temp.","OriginOfCondition":{"@odata.id":"/redfish/v1/Chassis/chassis/Sensors/CPU_Temp"},"EventTimestamp":"2026-02-06T14:30:00Z"}]}

id: 2
data: {"@odata.type":"#Event.v1_4_0.Event","Id":"2","Name":"Event Array","Events":[{"EventType":"ResourceUpdated","MessageId":"ResourceEvent.1.0.ResourceChanged","OriginOfCondition":{"@odata.id":"/redfish/v1/Systems/system"},"EventTimestamp":"2026-02-06T14:31:15Z"}]}

```

Each message has an `id:` line (for reconnection tracking) and a `data:` line containing the JSON event payload. Messages are separated by a blank line.

### SSE Filtering with Query Parameters

You can filter the SSE stream using query parameters to receive only the events you need:

```bash
# Filter by registry prefix
curl -k -u root:0penBmc -N \
    -H "Accept: text/event-stream" \
    "https://localhost/redfish/v1/EventService/SSE?\$filter=RegistryPrefix%20eq%20OpenBMC"

# Filter by resource type
curl -k -u root:0penBmc -N \
    -H "Accept: text/event-stream" \
    "https://localhost/redfish/v1/EventService/SSE?\$filter=ResourceType%20eq%20Chassis"

# Filter by message ID
curl -k -u root:0penBmc -N \
    -H "Accept: text/event-stream" \
    "https://localhost/redfish/v1/EventService/SSE?\$filter=MessageId%20eq%20OpenBMC.0.1.SensorThresholdWarning"
```

{: .note }
> URL-encode special characters in filter expressions. The `$` in `$filter` must be escaped or quoted in shell commands. The space around `eq` is required.

### SSE with Python

```python
#!/usr/bin/env python3
"""Listen for Redfish SSE events from OpenBMC."""
import requests
import json
import urllib3

# Disable TLS warnings for self-signed certificates
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

BMC_HOST = "https://localhost"
USERNAME = "root"
PASSWORD = "0penBmc"

url = f"{BMC_HOST}/redfish/v1/EventService/SSE"
headers = {"Accept": "text/event-stream"}

with requests.get(url, auth=(USERNAME, PASSWORD),
                  headers=headers, stream=True, verify=False) as resp:
    resp.raise_for_status()
    buffer = ""
    for chunk in resp.iter_content(decode_unicode=True):
        buffer += chunk
        while "\n\n" in buffer:
            message, buffer = buffer.split("\n\n", 1)
            for line in message.strip().split("\n"):
                if line.startswith("data: "):
                    event = json.loads(line[6:])
                    for e in event.get("Events", []):
                        print(f"[{e.get('EventTimestamp')}] "
                              f"{e.get('MessageId')}: {e.get('Message')}")
```

---

## Telemetry Metric Reports

The TelemetryService collects sensor readings at defined intervals and stores them as metric reports. This is more efficient than polling individual sensor endpoints repeatedly.

### Get TelemetryService Capabilities

```bash
bmcurl https://localhost/redfish/v1/TelemetryService | jq
```

Key properties in the response include `MaxReports` (maximum number of reports), `MinCollectionInterval` (shortest allowed sampling period, e.g., `"PT10S"`), and links to `MetricReportDefinitions` and `MetricReports` collections.

### Create a MetricReportDefinition

A MetricReportDefinition specifies which metrics to collect, how often, and where to store the results.

```bash
bmcurl -X POST \
    -H "Content-Type: application/json" \
    -d '{
        "Id": "ThermalMetrics",
        "Name": "Thermal Monitoring Report",
        "MetricReportDefinitionType": "Periodic",
        "ReportActions": ["LogToMetricReportsCollection"],
        "ReportUpdates": "Overwrite",
        "Schedule": {
            "RecurrenceInterval": "PT30S"
        },
        "Metrics": [
            {
                "MetricId": "CPUTemp",
                "MetricProperties": [
                    "/redfish/v1/Chassis/chassis/Sensors/CPU_Temp"
                ]
            },
            {
                "MetricId": "InletTemp",
                "MetricProperties": [
                    "/redfish/v1/Chassis/chassis/Sensors/Inlet_Temp"
                ]
            }
        ]
    }' \
    https://localhost/redfish/v1/TelemetryService/MetricReportDefinitions
```

### MetricReportDefinition Properties

| Property | Type | Description |
|----------|------|-------------|
| `Id` | string | Unique identifier for this definition |
| `MetricReportDefinitionType` | string | `"Periodic"` (timed) or `"OnChange"` (event-driven) or `"OnRequest"` (manual) |
| `ReportActions` | array | `"LogToMetricReportsCollection"` stores report; `"RedfishEvent"` sends as event |
| `ReportUpdates` | string | `"Overwrite"` replaces last report; `"AppendStopsWhenFull"` accumulates |
| `Schedule.RecurrenceInterval` | duration | ISO 8601 duration (e.g., `"PT30S"` = 30 seconds, `"PT5M"` = 5 minutes) |
| `Metrics[].MetricId` | string | Label for this metric in the report |
| `Metrics[].MetricProperties` | array | Redfish sensor URIs to sample |

### List MetricReportDefinitions

```bash
bmcurl https://localhost/redfish/v1/TelemetryService/MetricReportDefinitions | jq
```

### Get a Specific MetricReportDefinition

```bash
bmcurl https://localhost/redfish/v1/TelemetryService/MetricReportDefinitions/ThermalMetrics | jq
```

### Delete a MetricReportDefinition

```bash
bmcurl -X DELETE \
    https://localhost/redfish/v1/TelemetryService/MetricReportDefinitions/ThermalMetrics
```

### Retrieve a Metric Report

Once collection runs, retrieve the latest report:

```bash
bmcurl https://localhost/redfish/v1/TelemetryService/MetricReports/ThermalMetrics | jq
```

Example response:

```json
{
    "@odata.id": "/redfish/v1/TelemetryService/MetricReports/ThermalMetrics",
    "@odata.type": "#MetricReport.v1_4_0.MetricReport",
    "Id": "ThermalMetrics",
    "Name": "Thermal Monitoring Report",
    "ReportSequence": "42",
    "Timestamp": "2026-02-06T14:35:00Z",
    "MetricValues": [
        {
            "MetricId": "CPUTemp",
            "MetricValue": "47.5",
            "Timestamp": "2026-02-06T14:35:00Z",
            "MetricProperty": "/redfish/v1/Chassis/chassis/Sensors/CPU_Temp"
        },
        {
            "MetricId": "InletTemp",
            "MetricValue": "28.0",
            "Timestamp": "2026-02-06T14:35:00Z",
            "MetricProperty": "/redfish/v1/Chassis/chassis/Sensors/Inlet_Temp"
        }
    ]
}
```

### Receive Metric Reports as Events

To receive metric reports through an event subscription instead of polling, create a subscription with `EventFormatType` set to `"MetricReport"`:

```bash
bmcurl -X POST \
    -H "Content-Type: application/json" \
    -d '{
        "Destination": "https://my-monitoring-server:8443/telemetry",
        "Protocol": "Redfish",
        "EventFormatType": "MetricReport",
        "Context": "bmc-01-telemetry"
    }' \
    https://localhost/redfish/v1/EventService/Subscriptions
```

Then add `"RedfishEvent"` to the `ReportActions` array in the MetricReportDefinition to trigger delivery.

---

## Subscription Limits and Lifecycle

### Subscription Limits

OpenBMC enforces practical limits on event subscriptions to protect BMC resources:

| Limit | Default Value | Description |
|-------|---------------|-------------|
| Maximum subscriptions | 20 | Total push + SSE subscriptions allowed |
| Maximum SSE connections | 10 | Concurrent SSE streams |
| Delivery retry attempts | 3 | POST retries on failure before marking error |
| Delivery retry interval | 60 seconds | Delay between retry attempts |

{: .warning }
> Exceeding the subscription limit returns HTTP 400 with a `CreateLimitReachedForResource` message. Delete unused subscriptions before creating new ones.

### Subscription Expiration

Subscriptions do not expire by default. They persist until explicitly deleted or the BMC is factory-reset. Monitor your subscription count and clean up stale entries to stay within the limit.

### Retry Behavior

When a push delivery fails (destination unreachable, HTTP error response), bmcweb follows this retry sequence:

1. Wait `DeliveryRetryIntervalSeconds` (default 60s).
2. Retry the POST.
3. Repeat up to `DeliveryRetryAttempts` times (default 3).
4. After all retries are exhausted, the subscription enters a suspended state.

```bash
# Configure retry parameters
bmcurl -X PATCH \
    -H "Content-Type: application/json" \
    -d '{
        "DeliveryRetryAttempts": 5,
        "DeliveryRetryIntervalSeconds": 30
    }' \
    https://localhost/redfish/v1/EventService
```

### SSE Connection Lifecycle

SSE connections remain open until one of these occurs:
- The client closes the connection (e.g., Ctrl+C).
- The BMC restarts or bmcweb restarts.
- An idle timeout expires (if configured).
- The maximum SSE connection limit is reached and the oldest stream is evicted.

{: .tip }
> Implement automatic reconnection in your SSE client. Use the `id:` field from the last received event to track your position. After reconnecting, you may miss events that occurred during the disconnect window.

---

## Code Examples

### Example: Telemetry Collection Script

```bash
#!/usr/bin/env bash
# telemetry-collector.sh - Create metric report and poll results
set -euo pipefail

BMC_HOST="https://localhost"
CREDS="root:0penBmc"
alias bmcurl="curl -sk -u ${CREDS}"

# Create a MetricReportDefinition for thermal data
bmcurl -X POST \
    -H "Content-Type: application/json" \
    -d '{
        "Id": "EnvMetrics",
        "Name": "Environmental Metrics",
        "MetricReportDefinitionType": "Periodic",
        "ReportActions": ["LogToMetricReportsCollection"],
        "ReportUpdates": "Overwrite",
        "Schedule": {"RecurrenceInterval": "PT60S"},
        "Metrics": [
            {
                "MetricId": "CPUTemp",
                "MetricProperties": ["/redfish/v1/Chassis/chassis/Sensors/CPU_Temp"]
            }
        ]
    }' \
    "${BMC_HOST}/redfish/v1/TelemetryService/MetricReportDefinitions"

echo "MetricReportDefinition created. Polling every 65s (Ctrl+C to stop)..."

while true; do
    sleep 65
    echo "--- $(date -Iseconds) ---"
    bmcurl "${BMC_HOST}/redfish/v1/TelemetryService/MetricReports/EnvMetrics" | \
        jq '.MetricValues[] | {MetricId, MetricValue, Timestamp}'
done
```

See the complete examples in the [examples/redfish-events/](https://github.com/MichaelTien8901/openbmc-guide-tutorial/tree/master/docs/examples/redfish-events) directory.

---

## Troubleshooting

### Issue: Subscription Creation Returns 400 or 403

**Symptom**: `POST` to `/redfish/v1/EventService/Subscriptions` returns HTTP 400 or 403.

**Cause**: The subscription limit has been reached, or push-style notifications are not enabled at build time.

**Solution**:
1. Check existing subscriptions and delete stale ones:
   ```bash
   bmcurl https://localhost/redfish/v1/EventService/Subscriptions | jq '.Members'
   bmcurl -X DELETE https://localhost/redfish/v1/EventService/Subscriptions/<id>
   ```
2. Verify that `insecure-push-style-notification` is enabled in your bmcweb build:
   ```bash
   journalctl -u bmcweb | grep -i "push"
   ```
3. Rebuild bmcweb with the flag enabled if needed.

### Issue: Push Events Not Arriving at Destination

**Symptom**: Subscription exists but no HTTP POST requests reach the destination server.

**Cause**: Network connectivity, TLS certificate validation, or firewall blocking the BMC's outbound connection.

**Solution**:
1. Test basic connectivity from the BMC:
   ```bash
   curl -k https://my-monitoring-server:8443/
   ```
2. Check bmcweb logs for delivery errors:
   ```bash
   journalctl -u bmcweb -f | grep -i "event\|subscription\|delivery"
   ```
3. Verify the destination URL is reachable from the BMC network namespace.

### Issue: SSE Stream Closes Immediately

**Symptom**: `curl` to the SSE endpoint returns immediately with no data or an error.

**Cause**: Missing `Accept: text/event-stream` header, authentication failure, or SSE connection limit reached.

**Solution**:
1. Ensure you include the correct headers and authentication:
   ```bash
   curl -k -u root:0penBmc -N \
       -H "Accept: text/event-stream" \
       https://localhost/redfish/v1/EventService/SSE
   ```
2. Check for open SSE connections consuming the limit:
   ```bash
   ss -tnp | grep bmcweb
   ```
3. Restart bmcweb to clear stale connections if needed:
   ```bash
   systemctl restart bmcweb
   ```

### Issue: MetricReport Returns Empty or 404

**Symptom**: The MetricReport URI returns 404 or a report with no `MetricValues`.

**Cause**: The MetricReportDefinition has not yet collected data (first interval not elapsed), or the sensor URIs in `MetricProperties` are incorrect.

**Solution**:
1. Wait at least one collection interval after creating the definition.
2. Verify the sensor URIs exist:
   ```bash
   bmcurl https://localhost/redfish/v1/Chassis/chassis/Sensors | jq '.Members[]."@odata.id"'
   ```
3. Check the MetricReportDefinition status:
   ```bash
   bmcurl https://localhost/redfish/v1/TelemetryService/MetricReportDefinitions/ThermalMetrics | jq '.Status'
   ```

### Debug Commands

```bash
# Check bmcweb service status
systemctl status bmcweb

# View event-related logs
journalctl -u bmcweb -f --grep="event|subscription|telemetry|metric"

# List active network connections to bmcweb
ss -tnp | grep bmcweb

# Query D-Bus for sensor availability
busctl tree xyz.openbmc_project.HwmonTempSensor

# Check dbus-sensors services
systemctl list-units | grep sensor
```

---

## References

### Official Resources
- [bmcweb Repository](https://github.com/openbmc/bmcweb) - Source code for EventService and TelemetryService handlers
- [phosphor-dbus-interfaces](https://github.com/openbmc/phosphor-dbus-interfaces) - D-Bus interface definitions for sensors and logging
- [OpenBMC Documentation](https://github.com/openbmc/docs)

### Related Guides
- [Redfish Guide]({% link docs/04-interfaces/02-redfish-guide.md %}) - Redfish fundamentals, authentication, and core operations

### External Documentation
- [DMTF Redfish EventService Schema](https://redfish.dmtf.org/schemas/v1/EventService.json)
- [DMTF Redfish TelemetryService Schema](https://redfish.dmtf.org/schemas/v1/TelemetryService.json)
- [DMTF Redfish Specification - Eventing](https://www.dmtf.org/standards/redfish)
- [Server-Sent Events (SSE) Specification](https://html.spec.whatwg.org/multipage/server-sent-events.html)
- [ISO 8601 Duration Format](https://en.wikipedia.org/wiki/ISO_8601#Durations)

---

{: .note }
**Tested on**: OpenBMC master, QEMU ast2600-evb. Push-style subscriptions require the `insecure-push-style-notification` build flag. SSE and TelemetryService are available with default bmcweb configuration. Sensor availability on QEMU may vary depending on the machine model and virtual sensor configuration.
