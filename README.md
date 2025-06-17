# OTLP Stdout Language Layers

This repository provides AWS Lambda layers that enhance the standard OpenTelemetry (OTEL) layers by adding a efficient transport method for your telemetry data: **OTLP over stdout**.

By using these layers, you can configure your Lambda functions to export traces directly to standard output, unlocking significant performance and operational benefits.

The OTLP Stdout Span Exporter is a lightweight, efficient span exporter that writes OTLP spans to stdout. It is designed to be used in AWS Lambda functions and is a great way to get started with OpenTelemetry. The packages are available on [PyPI](https://pypi.org/project/otlp-stdout-span-exporter/) and [npm](https://www.npmjs.com/package/@dev7a/otlp-stdout-span-exporter) if you want to use them in your own projects.

---
## Motivation

In modern serverless architectures, sending observability data via traditional network exporters (like OTLP over HTTP or gRPC) can introduce unnecessary overhead. Every millisecond counts, and network operations are a common source of latency and configuration complexity.

The `otlp-stdout` approach simplifies this by treating telemetry as a logging concern. Instead of pushing data from the function, it writes compressed OTLP spans to `stdout`. This stream is automatically captured by the Lambda runtime and sent to CloudWatch Logs. From there, a log-forwarding pipeline can parse the OTLP data and send it to any observability backend, turning your logging pipeline into a robust and efficient telemetry pipeline.

## Key Benefits

Using `otlp-stdout` provides several key advantages over traditional network-based exporters:

- **Reduced Cold Start & Latency**: By eliminating the need for the Lambda function to establish a network connection to a collector, we remove network setup overhead from the critical path. This reduces both cold start times and per-invocation latency, as writing to stdout is significantly faster than a network round-trip.

- **Simplified IAM Permissions**: Functions no longer need VPC access or `ec2:CreateNetworkInterface` permissions to export telemetry. The only permission required is the default ability to write to CloudWatch Logs, simplifying your security posture.

- **More Reliable Data Ingestion**: The process leverages the highly reliable, at-least-once delivery mechanism of AWS CloudWatch Logs. This eliminates the risk of dropped spans due to transient network issues between the Lambda function and an OTLP collector.

- **Cost-Effective**: Reducing cold starts and latency can reduce costs by reducing the number of concurrent function executions and billed duration.

---
## How It Works

This project builds and packages **full, self-contained Lambda layers** with the `otlp-stdout` exporter already integrated. This makes them a simple, drop-in replacement for the standard upstream OpenTelemetry layers.

Our build process clones the official [opentelemetry-lambda](https://github.com/open-telemetry/opentelemetry-lambda) repository, injects the `otlp-stdout` exporter, and packages everything into a ready-to-use layer. This is the recommended approach for both Python and Node.js as it guarantees compatibility.

---
## Repository layout
```
otlp-stdout-language-layers/
├── Makefile                     # build targets for both approaches
├── python/
│   └── Dockerfile               # overlay layer build (future use)
├── nodejs/
│   ├── Dockerfile               # overlay layer build (future use)
│   ├── patch-full-layer.mjs     # configureExporterMap implementation
│   ├── wrapper-override.patch   # upstream extensibility patch
│   └── otel-handler             # custom handler script
└── dist/                        # build artifacts appear here
```

---
## Build-time configuration
All configuration is passed as environment variables when you invoke `make`.

| Variable | Default | Description |
|----------|---------|-------------|
| `AWS_REGION` | `us-east-1` | AWS region for publishing layers. |
| `UPSTREAM_REPO` | `https://github.com/open-telemetry/opentelemetry-lambda.git` | Upstream repository to clone for full builds. |
| `UPSTREAM_BRANCH` | `main` | Branch/tag to build from. |
| `EXPORTER_VERSION` | `latest` | Version of otlp-stdout-span-exporter to include. |
| `PY_BASE_LAYER_ARN` | `arn:aws:lambda:${AWS_REGION}:184161586896:layer:opentelemetry-python-0_14_0:1` | For overlay builds (future). |
| `NODE_BASE_LAYER_ARN` | `arn:aws:lambda:${AWS_REGION}:184161586896:layer:opentelemetry-nodejs-0_14_0:1` | For overlay builds (future). |

---
## Building

Prerequisites: Node.js, Python 3, and GNU Make.

```bash
# Build both layers
make build
```

## Publishing to AWS
Prerequisites: AWS CLI configured with appropriate permissions.

```bash
# Publish individual layers
make publish-python-layer
make publish-node-layer

# Publish both layers
make publish

# Show current layer ARNs
make show-arns
```

The publish targets will:
- Build the full layers from upstream source
- Upload them to your AWS account in the configured region
- Output the resulting layer ARNs

---
## Using the layers

1. Publish the layers to your AWS account (or use CI/CD)
2. Attach **one** layer to your Lambda function
3. Set the wrapper environment variable:
   * Python: `AWS_LAMBDA_EXEC_WRAPPER=/opt/otel-instrument`
   * Node.js: `AWS_LAMBDA_EXEC_WRAPPER=/opt/otel-handler`
4. Configure the exporter:
   ```
   OTEL_TRACES_EXPORTER=otlpstdout
   OTLP_STDOUT_SPAN_EXPORTER_COMPRESSION_LEVEL=6   # optional, default 6
   ```

---
## Example layer configuration

**Python Lambda (Full Layer):**
```yaml
Layers:
  - arn:aws:lambda:us-east-1:961341555982:layer:otlp-stdout-python-main:2
Environment:
  Variables:
    AWS_LAMBDA_EXEC_WRAPPER: /opt/otel-instrument
    OTEL_TRACES_EXPORTER: otlpstdout
```

**Node.js Lambda (Full Layer):**
```yaml
Layers:
  - arn:aws:lambda:us-east-1:961341555982:layer:otlp-stdout-node-main:5
Environment:
  Variables:
    AWS_LAMBDA_EXEC_WRAPPER: /opt/otel-handler
    OTEL_TRACES_EXPORTER: otlpstdout
```

---

### Future Direction: Overlay Layers

An alternative approach to rebuilding the full layers could be to use a thin "overlay" layer that only contains the `otlp-stdout` exporter and injects it into the standard, unmodified upstream OTEL layer.

- **Python**: This already works due to Python's native entry point discovery system. You can build and use this via the `make build-python-layer-overlay` target.
- **Node.js**: This is not yet possible because the upstream Node.js layer is a bundled webpack artifact that does not support dynamic module loading. The extensibility enhancements included in this project (see "Upstream Contribution") are a step toward making this a reality.

---
## Development

### Clean up build artifacts
```bash
make clean-dist    # Remove build artifacts from the dist/ directory
make clean-clone   # Remove the cloned upstream repository
make clean         # Remove both dist/ and the clone directory
```

All clean targets include confirmation prompts for safety.

---
## License
Apache-2.0, same as the upstream OpenTelemetry projects.
