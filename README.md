# OTLP/STDOUT Language Layers

This repository provides AWS Lambda layers that enhance the standard [OpenTelemetry (OTEL) layers](https://github.com/open-telemetry/opentelemetry-lambda) by adding a **OTLP over stdout** transport method for the traces signal, unlocking significant performance and operational benefits.

This is done by injecting the OTLP Stdout Span Exporter in the default telemetry pipeline. This exporter is a lightweight, efficient span exporter that writes OTLP spans to stdout as a protobuf gzip compressed JSON record. The packages for the exporter and the documentation are available on mpm and pypi if you want to use them in your own projects:

[![npm](https://img.shields.io/npm/v/%40dev7a%2Fotlp-stdout-span-exporter?style=for-the-badge)](https://www.npmjs.com/package/@dev7a/otlp-stdout-span-exporter)  [![PyPI](https://img.shields.io/pypi/v/otlp-stdout-span-exporter?style=for-the-badge)](https://pypi.org/project/otlp-stdout-span-exporter/)

> [!NOTE]
> This project is a work in progress and is subject to change. Use at your own risk.

## Motivation

In modern serverless architectures, sending observability data via traditional network exporters (like OTLP over HTTP or gRPC) can introduce unnecessary overhead. Every millisecond counts, and network operations are a common source of latency and configuration complexity.

The `otlp-stdout-span-exporter` simplifies this by treating telemetry as a logging concern. Instead of pushing data from the function, it writes compressed OTLP spans to `stdout` (or to a named pipe for use with extensions). This stream is automatically captured by the Lambda runtime and sent to CloudWatch Logs. From there, a otlp-forwarding pipeline can parse the OTLP data and send it to any observability backend.

> [!NOTE]
> Currently only the traces signal is supported, other signals (logs and metrics) will still be using the standard OTLP over http or gRPC methods. If you are using these signals, you should use the standard OTEL layers.


## Key Benefits

Using this _"OTLP over stdout"_ approach provides several key advantages over traditional network-based exporters:

- **Reduced Cold Start & Latency**: By eliminating the need for the Lambda function to establish a network connection to a collector, we remove network setup overhead from the critical path. This reduces both cold start times and per-invocation latency, as writing to stdout is significantly faster than a network round-trip.

- **Simplified IAM Permissions**: Functions no longer need VPC access or `ec2:CreateNetworkInterface` permissions to export telemetry. The only permission required is the default ability to write to CloudWatch Logs, simplifying your security posture.

- **More Reliable Data Ingestion**: The process leverages the highly reliable, at-least-once delivery mechanism of AWS CloudWatch Logs. This eliminates the risk of dropped spans due to transient network issues between the Lambda function and an OTLP collector.

- **Cost-Effective**: Reducing cold starts and latency can reduce costs by reducing the number of concurrent function executions and billed duration.

## How It Works

This project builds and packages **full, self-contained Lambda layers** with the `otlp-stdout-span-exporter` pacakge already integrated. This makes them a simple, drop-in replacement for the standard upstream OpenTelemetry layers.

The build process clones the official [opentelemetry-lambda](https://github.com/open-telemetry/opentelemetry-lambda) repository, patches a couple of files to inject the exporter, and packages everything into a ready-to-use layer.

## Build-time configuration
All configuration is passed as environment variables when you invoke `make`.

| Variable | Default | Description |
|----------|---------|-------------|
| `AWS_REGION` | `us-east-1` | AWS region for publishing layers. |
| `UPSTREAM_REPO` | `https://github.com/open-telemetry/opentelemetry-lambda.git` | Upstream repository to clone for full builds. |
| `UPSTREAM_BRANCH` | `main` | Branch/tag to build from. |
| `EXPORTER_VERSION` | `latest` | Version of otlp-stdout-span-exporter to include. |

## Building

Prerequisites: Node.js, Python 3, and GNU Make.

```bash
# Build both layers
make build
```

## Local Development Publishing
Prerequisites: AWS CLI configured with appropriate permissions.

For local development and testing, you can publish layers to your AWS account using the Makefile:

```bash
# Publish individual layers (for local development)
make publish-python-layer
make publish-node-layer

# Publish both layers (for local development)
make publish

# Show current local layer ARNs
make show-arns
```

The local publish targets will:
- Build the full layers from upstream source
- Upload them to your AWS account in the configured region with `local-` prefix
- Output the resulting layer ARNs

> [!NOTE]  
> These Makefile targets are intended for **local development only**. For production releases, use the **Manual Layer Publish** workflow in GitHub Actions which provides multi-region publishing, release group management, and proper versioning.

---
## Using the layers

1. Publish the layers to your AWS account (or use CI/CD)
2. Attach **one** layer to your Lambda function
3. Set the wrapper environment variable (current v0.14.0 standards):
   * Python: `AWS_LAMBDA_EXEC_WRAPPER=/opt/otel-instrument`
   * Node.js: `AWS_LAMBDA_EXEC_WRAPPER=/opt/otel-handler`
4. Configure the exporter:
   ```
   OTEL_TRACES_EXPORTER=otlpstdout
   OTLP_STDOUT_SPAN_EXPORTER_COMPRESSION_LEVEL=6   # optional, default 6
   ```
> [!IMPORTANT]
> **Future configuration for the python layer (post v0.14.0):**
> Following the OpenTelemetry community's standardization effort ([Issue #1788](https://github.com/open-telemetry/opentelemetry-lambda/issues/1788), [PR #1837](https://github.com/open-telemetry/opentelemetry-lambda/pull/1837)), all languages will standardize on `/opt/otel-handler`:so, fot **all languages** you should use `AWS_LAMBDA_EXEC_WRAPPER=/opt/otel-handler`


## Example layer configuration

**Python Lambda:**
```yaml
Layers:
  - arn:aws:lambda:us-east-1:961341555982:layer:otlp-stdout-python-main:2
Environment:
  Variables:
    AWS_LAMBDA_EXEC_WRAPPER: /opt/otel-instrument  # current standard for v0.14.0
    OTEL_TRACES_EXPORTER: otlpstdout
```

**Node.js Lambda:**
```yaml
Layers:
  - arn:aws:lambda:us-east-1:961341555982:layer:otlp-stdout-node-main:5
Environment:
  Variables:
    AWS_LAMBDA_EXEC_WRAPPER: /opt/otel-handler
    OTEL_TRACES_EXPORTER: otlpstdout
```

## Development

### Clean up build artifacts
```bash
make clean-dist    # Remove build artifacts from the dist/ directory
make clean-clone   # Remove the cloned upstream repository
make clean         # Remove both dist/ and the clone directory
```

All clean targets include confirmation prompts for safety.


## CI/CD Workflows for OTLP Stdout Language Layers

### Continuous Integration (CI)

#### `ci-python.yml`
- **Triggers**: Push/PR to `main` when Python files, Makefile, or workflow changes
- **Purpose**: Build and test Python layers with Python 3.13
- **Jobs**:
  - Build full Python layer from upstream source
  - Verify layer contents

#### `ci-nodejs.yml`
- **Triggers**: Push/PR to `main` when Node.js files, Makefile, or workflow changes
- **Purpose**: Build and test Node.js layers with Node.js 22
- **Jobs**:
  - Build full Node.js layer from upstream source
  - Verify layer contents

### Manual Publishing Workflow

#### `publish-layer-manual.yml`
- **Triggers**: Manual dispatch from GitHub UI
- **Purpose**: On-demand layer publishing with custom parameters
- **Options**:
  - Choose language (Python or Node.js - one at a time)
  - Specify exporter version (default: latest)
  - Select AWS regions (individual region or all 13 regions)
  - Set release group (free text, default: beta)
  - Set upstream branch/tag with smart handling:
    - `v0.14.0` → Auto-constructs `layer-python/0.14.0` or `layer-nodejs/0.14.0`
    - `layer-python/0.14.0` → Uses exactly as specified (with validation)
    - `main`, branches, commits → Uses as-is for development builds
- **Features**:
  - Smart tag construction from semantic versions (reduces typos)
  - Automatic GitHub release creation for version tags
  - Real layer ARN documentation in release notes
  - Input validation to prevent language/tag mismatches

### Utility Workflows

#### `layer-publish.yml`
- **Purpose**: Reusable workflow for publishing layers to AWS Lambda
- **Used by**: All release and manual publish workflows
- **Features**:
  - Configurable layer naming
  - Multi-region publishing
  - Public layer permissions
  - Version tracking


## Usage Instructions

### Publishing Layers

1. Go to **Actions** → **Manual Layer Publish** in the GitHub UI
2. Click **Run workflow**
3. Configure the parameters:
   - Language: Choose Python or Node.js (one at a time)
   - Exporter version: Specify version or use "latest"
   - AWS regions: Select specific regions or "all" (13 regions)
   - Release group: Enter custom name (default: "beta") - affects layer naming
   - Upstream branch: See options below

### Upstream Branch Options

The manual workflow supports several upstream branch/tag formats:

#### **Semantic Versions (Recommended for Releases)**
- **Input**: `v0.14.0`
- **Result**: Auto-constructs language-specific tags
  - Python: `layer-python/0.14.0`
  - Node.js: `layer-nodejs/0.14.0`
- **Creates Release**: Yes, with tag matching the constructed language-specific tag
- **Benefits**: Reduces typos, same input works for both languages

#### **Language-Specific Tags**
- **Input**: `layer-python/0.14.0` or `layer-nodejs/0.14.0`
- **Result**: Uses tag exactly as specified
- **Creates Release**: Yes, with the same tag
- **Validation**: Must match selected language (prevents mismatches)

#### **Generic References**
- **Input**: `main`, `feature-branch`, commit hash
- **Result**: Uses reference as-is for building
- **Creates Release**: No
- **Use Case**: Development, testing, custom builds

### Examples

**Production Release - Python layer v0.14.0:**
```
Language: python
Upstream branch: v0.14.0  ← Simple and typo-free!
Release group: prod
```
Creates GitHub release with tag `layer-python/0.14.0`

**Production Release - Node.js layer v0.14.0:**
```
Language: nodejs
Upstream branch: v0.14.0  ← Same input, different language
Release group: prod
```
Creates GitHub release with tag `layer-nodejs/0.14.0`

**Beta Release:**
```
Language: python
Upstream branch: v0.14.0
Release group: beta
```
Creates GitHub release with tag `layer-python/0.14.0-beta`

**Development build:**
```
Language: python
Upstream branch: main
Release group: dev
```
No GitHub release created

### Required Secrets

Configure these secrets in your GitHub repository:

- `OTEL_LAMBDA_LAYER_PUBLISH_ROLE_ARN`: AWS IAM role ARN for publishing Lambda layers
- `GITHUB_TOKEN`: Automatically provided by GitHub

The IAM role should have permissions for:
- `lambda:PublishLayerVersion`
- `lambda:AddLayerVersionPermission`
- `lambda:ListLayerVersions`

### Supported AWS Regions

All workflows publish to these 13 regions:
- **Canada**: ca-central-1, ca-west-1
- **Europe**: eu-central-1, eu-central-2, eu-north-1, eu-south-1, eu-south-2, eu-west-1, eu-west-2, eu-west-3
- **US**: us-east-1, us-east-2, us-west-2

### Monitoring

- **CI workflows**: Run on every PR to ensure quality
- **Release workflows**: Create GitHub releases with artifacts
- **Manual workflows**: Provide flexibility for testing and hotfixes

All workflows provide detailed logging and will create GitHub annotations for important events and warnings. 

---
## License
MIT