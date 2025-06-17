# CI/CD Workflows for OTLP Stdout Language Layers

This directory contains GitHub Actions workflows for continuous integration and deployment of the OTLP Stdout Language Layers project.

## Workflow Overview

### Continuous Integration (CI)

#### `ci-python.yml`
- **Triggers**: Push/PR to `main` when Python files, Makefile, or workflow changes
- **Purpose**: Build and test Python layers across multiple Python versions (3.8-3.13)
- **Jobs**:
  - Build full Python layer from upstream source
  - Verify layer contents

#### `ci-nodejs.yml`
- **Triggers**: Push/PR to `main` when Node.js files, Makefile, or workflow changes
- **Purpose**: Build and test Node.js layers across multiple Node.js versions (18, 20, 22)
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
  - Build Python layer with tagged exporter version
  - Publish to 16 AWS regions
  - Upload artifacts to GitHub release

#### `release-layer-nodejs.yml`
- **Triggers**: Tag push matching `layer-nodejs/**`
- **Purpose**: Build and publish Node.js layers to AWS Lambda in all regions
- **Jobs**:
  - Create GitHub release
  - Build Node.js layer with tagged exporter version
  - Publish to 16 AWS regions
  - Upload artifacts to GitHub release

### Manual Workflows

#### `publish-layer-manual.yml`
- **Triggers**: Manual dispatch from GitHub UI
- **Purpose**: On-demand layer publishing with custom parameters
- **Options**:
  - Choose language (Python, Node.js, or both)
  - Specify exporter version
  - Select AWS regions
  - Choose release environment (dev/prod)
  - Set upstream branch

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
   - Language: Choose Python, Node.js, or both
   - Exporter version: Specify version or use "latest"
   - AWS regions: Select specific regions or "all"
   - Release group: Choose "dev" for testing or "prod" for production
   - Upstream branch: Usually "main" unless testing specific branches

### Required Secrets

Configure these secrets in your GitHub repository:

- `OTEL_LAMBDA_LAYER_PUBLISH_ROLE_ARN`: AWS IAM role ARN for publishing Lambda layers
- `GITHUB_TOKEN`: Automatically provided by GitHub

The IAM role should have permissions for:
- `lambda:PublishLayerVersion`
- `lambda:AddLayerVersionPermission`
- `lambda:ListLayerVersions`

### Monitoring

- **CI workflows**: Run on every PR to ensure quality
- **Release workflows**: Create GitHub releases with artifacts
- **Manual workflows**: Provide flexibility for testing and hotfixes

All workflows provide detailed logging and will create GitHub annotations for important events and warnings. 