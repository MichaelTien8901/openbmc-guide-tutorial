# Redfish EventService and Telemetry Examples

Shell scripts for working with Redfish EventService (push events, SSE streaming)
and TelemetryService (periodic metric reports) on OpenBMC.

> **Runs from a remote host** -- these scripts use curl to interact with the BMC's
> Redfish API over HTTPS. They do not need to run on the BMC itself.

## Quick Start

```bash
# Set BMC connection variables
export BMC_HOST="localhost:2443"
export BMC_USER="root"
export BMC_PASS="0penBmc"

# Create a push event subscription
./create-subscription.sh

# Listen for Server-Sent Events (SSE) in real time
./sse-listener.sh

# Create a periodic telemetry report for sensor data
./create-telemetry-report.sh

# List and manage existing subscriptions
./list-subscriptions.sh
```

## Scripts

| Script | Description |
|--------|-------------|
| `create-subscription.sh` | Create a push event subscription (POST to EventService/Subscriptions) |
| `sse-listener.sh` | Connect to SSE endpoint and display streaming events in real time |
| `create-telemetry-report.sh` | Create a MetricReportDefinition for periodic sensor data collection |
| `list-subscriptions.sh` | List, inspect, and delete existing event subscriptions |

## Environment Variables

All scripts accept the same connection variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `BMC_HOST` | `localhost:2443` | BMC hostname or IP with port |
| `BMC_USER` | `root` | Redfish authentication username |
| `BMC_PASS` | `0penBmc` | Redfish authentication password |

## Redfish EventService Overview

OpenBMC bmcweb implements the Redfish EventService, which provides two mechanisms
for asynchronous event delivery:

### Push Events (Subscriptions)

Clients register a callback URL. When events occur (sensor threshold crossed,
log entry created, etc.), the BMC sends an HTTP POST with the event payload to
each subscriber's `Destination` URL.

```
Client                          BMC (bmcweb)
  |                                |
  |-- POST Subscriptions --------->|  (register callback URL)
  |<-- 201 Created ----------------|
  |                                |
  |      ... event occurs ...      |
  |                                |
  |<-- POST event payload ---------|  (push to Destination)
  |-- 200 OK --------------------->|
```

### Server-Sent Events (SSE)

Clients open a long-lived HTTP connection to the SSE endpoint. Events are
streamed as `text/event-stream` data. No callback URL is needed -- the client
receives events on the same connection.

```
Client                          BMC (bmcweb)
  |                                |
  |-- GET EventService/SSE ------->|  (open SSE stream)
  |<-- 200 OK (text/event-stream) -|
  |                                |
  |      ... event occurs ...      |
  |                                |
  |<-- data: {event JSON} ---------|
  |<-- data: {event JSON} ---------|
  |         ...                    |
```

### Telemetry Service

The TelemetryService collects periodic sensor readings and stores them as
MetricReports. You define what to collect (MetricReportDefinition) and the BMC
generates reports at the specified interval.

```
MetricReportDefinition          MetricReport
  |                                |
  | Metrics: [sensor URIs]         | MetricValues: [
  | Schedule: every 60s            |   {MetricId, Value, Timestamp},
  | ReportActions: [LogToService]  |   ...
  |                                | ]
```

## Key Redfish Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/redfish/v1/EventService` | GET | EventService root (status, SSE URI, delivery retry policy) |
| `/redfish/v1/EventService/Subscriptions` | GET | List all event subscriptions |
| `/redfish/v1/EventService/Subscriptions` | POST | Create a new push event subscription |
| `/redfish/v1/EventService/Subscriptions/{Id}` | GET/DELETE | View or remove a specific subscription |
| `/redfish/v1/EventService/SSE` | GET | SSE streaming endpoint (text/event-stream) |
| `/redfish/v1/TelemetryService` | GET | TelemetryService root |
| `/redfish/v1/TelemetryService/MetricReportDefinitions` | GET/POST | Manage metric report definitions |
| `/redfish/v1/TelemetryService/MetricReports` | GET | View collected metric reports |

## Event Types

Common Redfish event types available in OpenBMC:

| EventType | Description |
|-----------|-------------|
| `Alert` | Condition requiring attention (threshold crossed, hardware error) |
| `ResourceAdded` | New resource created (new log entry, new sensor discovered) |
| `ResourceRemoved` | Resource deleted |
| `ResourceUpdated` | Resource property changed (power state, sensor value) |
| `StatusChange` | Component status changed (OK to Warning, etc.) |

## Yocto Build Configuration

EventService and TelemetryService are enabled in bmcweb by default on most
OpenBMC builds. To explicitly enable telemetry:

```bitbake
# local.conf or machine .conf
EXTRA_OEMESON:pn-bmcweb = " \
    -Dredfish-telemetry-service=enabled \
"

IMAGE_INSTALL:append = " telemetry "
```

## Troubleshooting

```bash
# Check EventService status
curl -k -s -u root:0penBmc https://localhost:2443/redfish/v1/EventService | jq '.'

# Verify SSE support is enabled
curl -k -s -u root:0penBmc https://localhost:2443/redfish/v1/EventService \
    | jq '{ServerSentEventUri, ServiceEnabled}'

# Check bmcweb logs for subscription delivery errors
journalctl -u bmcweb -f

# Verify TelemetryService is available
curl -k -s -u root:0penBmc https://localhost:2443/redfish/v1/TelemetryService | jq '.'
```

## References

- [Redfish Guide](../../04-interfaces/02-redfish-guide.md) -- bmcweb architecture and Redfish patterns
- [DMTF Redfish EventService schema](https://redfish.dmtf.org/schemas/v1/EventService.json)
- [DMTF Redfish TelemetryService schema](https://redfish.dmtf.org/schemas/v1/TelemetryService.json)
- [Redfish Specification (DSP0266)](https://www.dmtf.org/standards/redfish) -- EventService chapter
- [bmcweb Repository](https://github.com/openbmc/bmcweb)
- [OpenBMC telemetry design](https://github.com/openbmc/docs/blob/master/designs/telemetry.md)
