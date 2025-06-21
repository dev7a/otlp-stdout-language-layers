# OpenTelemetry Lambda Performance Benchmark Results

This report contains performance benchmarks comparing different OpenTelemetry telemetry strategies across multiple Lambda runtimes and memory configurations.

## Overview

Please review the template.yaml for the complete list of functions and configurations used in this test.
This benchmark compares four distinct telemetry strategies:

- **OTel + Collector** (`*-otel-collector`): Auto-instrumented OpenTelemetry with traditional Lambda extension collectors
- **OTel Direct** (`*-otel-direct`): Auto-instrumented OpenTelemetry exporting directly to telemetry backends
- **OTel + Stdout** (`*-otel-stdout`): Auto-instrumented OpenTelemetry with stdout exporters
- **Manual Instrumentation** (`*-lite-sync`, `*-lite-async`): Lightweight manual instrumentation using `lambda-otel-lite` with synchronous and asynchronous span processing

> **Note:** All functions are configured to use a mock otlp endpoint implemented with API Gateway with the mock integration. This is intended to simulate a real otlp collector http v1/traces endpoint, and to guarantee consistently the lowest latency for all tests. _Keep in mind when evaluating these results that in the real world, the latency will likely be higher due to the network round trip and the collector's processing time._

> **Protocol Note:** The Node.js auto-instrumented functions using the OpenTelemetry layer (`*-otel-collector`, `*-otel-direct`) use `http/json` instead of `http/protobuf` for OTLP export to reduce cold start times, as the protobufjs library significantly increases bundle size and initialization overhead. However, Node.js stdout functions (`*-otel-stdout`) still use protobuf encoding (output to stdout), which explains their slightly longer initialization times. Python functions use `http/protobuf` for HTTP exports and protobuf encoding for stdout exports.


## Testbed Function

Each function is running a simple workload of creating a hierarchy of spans. The depth and number of iterations for span creation can be controlled via the event payload. The default used in this run is 4 iterations at depth 2. The functions are intentionally not doing anything else, to isolate the overhead of the telemetry system, so we are not doing I/O or other heavy computations.
In pseudocode, the workload is as follows:

```
DEFAULT_DEPTH = 2
DEFAULT_ITERATIONS = 4

function process_level(depth, iterations):
    if depth <= 0:
        return
    for i from 0 to iterations-1:
        start span "operation_depth_{depth}_iter_{i}"
        set span attributes: depth, iteration, payload (256 'x')
        process_level(depth - 1, iterations)

function handler(event, lambda_context):
    depth = event.depth or DEFAULT_DEPTH
    iterations = event.iterations or DEFAULT_ITERATIONS
    process_level(depth, iterations)
    return {
        statusCode: 200,
        body: {
            message: "Benchmark complete",
            depth: depth,
            iterations: iterations
        }
    }
```

## Metrics
The benchmarks compare several metrics:

- **Cold Start Performance**: Initialization time, server duration, and total cold start times
- **Warm Start Performance**: Client latency, server processing time, and extension overhead
- **Resource Usage**: Memory consumption across different configurations
- **Bytes Sent**: Bytes sent as response to the client (it's expected to be the same for all tests)

## Test Configuration

All tests were run with the following parameters:
- 100 invocations per function
- 10 concurrent requests
- AWS Lambda arm64 architecture
- Same payload size for all tests

See the [template.yaml](https://github.com/dev7a/otlp-stdout-language-layers/blob/main/perftest/template.yaml) for the complete list of functions and configurations used in this test.

**OTEL_EXPORTER_OTLP_PROTOCOL varies by function type:**
- **Python HTTP functions** (`python-otel-collector`, `python-otel-direct`): `http/protobuf`
- **Node.js HTTP functions** (`node-otel-collector`, `node-otel-direct`): `http/json` (to reduce cold start overhead from protobufjs library)
- **Stdout functions** (`*-otel-stdout`): Use protobuf encoding but output to stdout instead of HTTP
- **Manual functions** (`*-lite-*`): Not applicable (uses lambda-otel-lite)

**OTEL_EXPORTER_OTLP_ENDPOINT varies by function type:**
- **Collector functions** (`*-otel-collector`): `http://localhost:4318` (sends to collector extension)
- **Direct functions** (`*-otel-direct`): Mock API Gateway endpoint (bypasses collector)
- **Stdout functions** (`*-otel-stdout`): Uses `OTEL_TRACES_EXPORTER=otlpstdout` instead
- **Manual functions** (`*-lite-*`): Not applicable (uses lambda-otel-lite)
