# OTLP/STDOUT Language Layers

This repository provides AWS Lambda layers that enhance the standard [OpenTelemetry (OTEL) layers](https://github.com/open-telemetry/opentelemetry-lambda) by adding a efficient transport method for your telemetry data: **OTLP over stdout**.

By using these layers, you can configure your Lambda functions to export traces directly to standard output, unlocking significant performance and operational benefits.

The OTLP Stdout Span Exporter is a lightweight, efficient span exporter that writes OTLP spans to stdout. It is designed to be used in AWS Lambda functions and is a great way to get started with OpenTelemetry. The packages are available on [NPM](https://www.npmjs.com/package/@dev7a/otlp-stdout-span-exporter) and [PyPI](https://pypi.org/project/otlp-stdout-span-exporter/) and [if you want to use them in your own projects:

[![npm](https://img.shields.io/npm/v/%40dev7a%2Fotlp-stdout-span-exporter?style=for-the-badge)](https://www.npmjs.com/package/@dev7a/otlp-stdout-span-exporter)  [![PyPI](https://img.shields.io/pypi/v/otlp-stdout-span-exporter?style=for-the-badge)](https://pypi.org/project/otlp-stdout-span-exporter/)

> [!NOTE]
> This project is a work in progress and is subject to change. Use at your own risk.

---
## Motivation

In modern serverless architectures, sending observability data via traditional network exporters (like OTLP over HTTP or gRPC) can introduce unnecessary overhead. Every millisecond counts, and network operations are a common source of latency and configuration complexity.

The `otlp-stdout` approach simplifies this by treating telemetry as a logging concern. Instead of pushing data from the function, it writes compressed OTLP spans to `stdout`. This stream is automatically captured by the Lambda runtime and sent to CloudWatch Logs. From there, a log-forwarding pipeline can parse the OTLP data and send it to any observability backend, turning your logging pipeline into a robust and efficient telemetry pipeline.

> [!NOTE]
> Currently we are supporting only the traces signal, other signals (logs and metrics) will still be using the standard OTLP over http or gRPC methods. If you are using these signals, you should use the standard OTEL layers.



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

---
## Example layer configuration

**Python Lambda (Full Layer):**
```yaml
Layers:
  - arn:aws:lambda:us-east-1:961341555982:layer:otlp-stdout-python-main:2
Environment:
  Variables:
    AWS_LAMBDA_EXEC_WRAPPER: /opt/otel-instrument  # current standard for v0.14.0
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

#### `ci-makefile.yml`
- **Triggers**: Push/PR to `main` when Makefile or shell scripts change
- **Purpose**: Validate Makefile syntax and shell script quality
- **Jobs**:
  - Run shellcheck on all shell scripts
  - Validate Makefile syntax and targets

### Release Workflows

#### `release-layer-python.yml`
- **Triggers**: Tag push matching `layer-python/**`
- **Purpose**: Build and publish Python layers to AWS Lambda in all regions
- **Jobs**:
  - Create GitHub release
  - Build Python layer with latest exporter version from upstream tag
  - Publish to 13 AWS regions (Canada, Europe, US)
  - Upload artifacts to GitHub release
  - Finalize GitHub release with layer ARNs and usage instructions

#### `release-layer-nodejs.yml`
- **Triggers**: Tag push matching `layer-nodejs/**`
- **Purpose**: Build and publish Node.js layers to AWS Lambda in all regions
- **Jobs**:
  - Create GitHub release
  - Build Node.js layer with latest exporter version from upstream tag
  - Publish to 13 AWS regions (Canada, Europe, US)
  - Upload artifacts to GitHub release
  - Finalize GitHub release with layer ARNs and usage instructions

### Manual Workflows

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

### Creating a Release

1. **Tag the release**: Create and push a tag following the pattern:
   ```bash
   # For Python layer
   git tag layer-python/1.2.3
   git push origin layer-python/1.2.3
   
   # For Node.js layer
   git tag layer-nodejs/1.2.3
   git push origin layer-nodejs/1.2.3
   ```

2. **Monitor the workflow**: The release workflow will automatically:
   - Create a draft GitHub release
   - Build the layer with the specified exporter version
   - Publish to all AWS regions
   - Upload artifacts to the release

3. **Finalize the release**: Edit and publish the draft release on GitHub

### Manual Publishing

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

**Release Python layer v0.14.0:**
```
Language: python
Upstream branch: v0.14.0  ← Simple and typo-free!
Release group: prod
```
Creates GitHub release with tag `layer-python/0.14.0`

**Release Node.js layer v0.14.0:**
```
Language: nodejs
Upstream branch: v0.14.0  ← Same input, different language
Release group: prod
```
Creates GitHub release with tag `layer-nodejs/0.14.0`

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
Apache-2.0, same as the upstream OpenTelemetry projects.
