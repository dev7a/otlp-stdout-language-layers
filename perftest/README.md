# Language Layers Performance Test
**Benchmark your Lambda telemetry. Validate your configurations.**

This directory provides a comprehensive testbed for rigorously evaluating different OpenTelemetry (OTel) approaches on AWS Lambda, designed to be used with the `startled` CLI tool. Its **primary objective** is to compare the performance overhead, cold start impact, and overall characteristics of four distinct telemetry strategies:

1. **OTel + Collector**: Auto-instrumented OpenTelemetry with traditional Lambda extension collectors
2. **OTel Direct**: Auto-instrumented OpenTelemetry exporting directly to telemetry backends  
3. **OTel + Stdout**: Auto-instrumented OpenTelemetry with stdout exporters
4. **Manual Instrumentation**: Lightweight manual instrumentation using `lambda-otel-lite`

This comparison enables data-driven decisions about telemetry architecture trade-offs between functionality, performance overhead, and implementation complexity on serverless platforms.


The testbed facilitates this comparison across:
- Various Lambda runtimes (Node.js, Python).
- Different telemetry export strategies (collector, direct, stdout).
- Auto-instrumentation vs manual instrumentation with lambda-otel-lite approaches.
- Synchronous vs asynchronous span processing modes for manual instrumentation with lambda-otel-lite.

## Directory Structure

```
perftest/
├── README.md            # This file
├── run_benchmarks.sh    # Automation script for running complete benchmark suite
├── functions/           # Lambda function source code and configurations
│   ├── confmaps/        # Collector configuration files
│   │   ├── Makefile     # Makefile to package collector configs
│   │   └── otel/
│   │       └── collector.yaml
│   ├── nodejs/
│   │   ├── auto/        # Code for auto-instrumented Node.js functions
│   │   │   └── index.js
│   │   └── manual/      # Code for manually configured Node.js function
│   │       ├── index.js
│   │       └── init.js  # Helper for lambda-otel-lite
│   └── python/
│       ├── auto/        # Code for auto-instrumented Python functions
│       │   └── main.py
│       └── manual/      # Code for manually configured Python function
│           └── main.py
├── proxy/               # Source code for the proxy Lambda function
│   └── src/main.rs
├── samconfig.toml       # AWS SAM CLI configuration for deployment
├── template.yaml        # AWS SAM template defining all Lambda functions and resources
└── test-events/         # Directory for test event JSON files (if any)
```

## Benchmark Scope and Configurations

The `template.yaml` defines a suite of Lambda functions. Each function executes a common workload to ensure fair comparison: recursively creating a tree of spans to simulate application activity and stress the telemetry system. The depth and number of iterations for span creation can be controlled via the event payload.

### Common Workload
All benchmarked functions (except the proxy) perform the same core task:
- They receive `depth` and `iterations` parameters in their input event.
- They recursively create a hierarchy of spans. `depth` controls how many levels deep the hierarchy goes, and `iterations` controls how many child spans are created at each level.
- Each span includes attributes like `depth`, `iteration`, and a fixed-size `payload`.

This consistent workload allows for direct comparison of telemetry overhead across different setups.

### Configurations Under Test

The following configurations are benchmarked, comparing four distinct telemetry strategies across multiple Lambda runtimes:

#### Node.js (`nodejs22.x` runtime)
-   **`node-lite-sync`**:
    -   Code: `functions/nodejs/manual/`
    -   Instrumentation: Uses `@dev7a/lambda-otel-lite` with synchronous span processing. **Represents the manual lightweight approach with sync span flushing.**
-   **`node-lite-async`**:
    -   Code: `functions/nodejs/manual/`
    -   Instrumentation: Uses `@dev7a/lambda-otel-lite` with asynchronous span processing. **Represents the manual lightweight approach with async span flushing.**
-   **`node-otel-collector`**:
    -   Code: `functions/nodejs/auto/`
    -   Instrumentation: Auto-instrumented OpenTelemetry with collector extension. Exports OTLP to `localhost:4318` via the OpenTelemetry collector layer using `/opt/otel/collector.yaml`.
-   **`node-otel-direct`**:
    -   Code: `functions/nodejs/auto/`
    -   Instrumentation: Auto-instrumented OpenTelemetry with direct export. Bypasses collector and exports directly to the mock OTLP endpoint.
-   **`node-otel-stdout`**:
    -   Code: `functions/nodejs/auto/`
    -   Instrumentation: Auto-instrumented OpenTelemetry with stdout exporter. Uses `OTEL_TRACES_EXPORTER=otlpstdout` to output traces to stdout.

#### Python (`python3.13` runtime)
-   **`python-lite-sync`**:
    -   Code: `functions/python/manual/`
    -   Instrumentation: Uses `lambda-otel-lite` with synchronous span processing. **Represents the manual lightweight approach with sync span flushing.**
-   **`python-lite-async`**:
    -   Code: `functions/python/manual/`
    -   Instrumentation: Uses `lambda-otel-lite` with asynchronous span processing. **Represents the manual lightweight approach with async span flushing.**
-   **`python-otel-collector`**:
    -   Code: `functions/python/auto/`
    -   Instrumentation: Auto-instrumented OpenTelemetry with collector extension. Exports OTLP to `localhost:4318` via the OpenTelemetry collector layer using `/opt/otel/collector.yaml`.
-   **`python-otel-direct`**:
    -   Code: `functions/python/auto/`
    -   Instrumentation: Auto-instrumented OpenTelemetry with direct export. Bypasses collector and exports directly to the mock OTLP endpoint.
-   **`python-otel-stdout`**:
    -   Code: `functions/python/auto/`
    -   Instrumentation: Auto-instrumented OpenTelemetry with stdout exporter. Uses `OTEL_TRACES_EXPORTER=otlpstdout` to output traces to stdout.

### Supporting Resources
-   **`ProxyFunction`**: A Rust-based Lambda function (`proxy/src/main.rs`) used by the `startled` CLI (via the `--proxy` argument) to measure client-side duration from within the AWS network, minimizing local network latency impact on results.
-   **`CollectorConfiglLayer`**: A Lambda layer built from `functions/confmaps/` that packages the `collector.yaml` configuration file.
-   **`MockOTLPReceiver`**: An API Gateway endpoint defined in `template.yaml` that acts as a mock OTLP receiver. The collector configurations in `functions/confmaps/` are set up to send telemetry to this mock endpoint by default (via the `MOCK_OTLP_ENDPOINT` environment variable). This allows testing telemetry export paths without requiring a full backend observability platform and preventing variability in the results due to external factors.

## Prerequisites

1.  **AWS SAM CLI**: For deploying the CloudFormation stack. ([Installation Guide](https://docs.aws.amazon.com/serverless-application-model/latest/developerguide/install-sam-cli.html))
2.  **Rust & Cargo**: For building the Rust-based proxy function and installing the `startled` CLI tool. ([Installation Guide](https://www.rust-lang.org/tools/install))
3.  **Node.js & npm**: For Node.js based Lambda functions.
4.  **Python**: For Python-based Lambda functions.
5.  **Docker**: SAM CLI uses Docker to build Lambda deployment packages.
6.  The `startled` CLI tool must be installed. You can either:
    - Install from crates.io: `cargo install startled --version 0.3.3` (see https://crates.io/crates/startled/0.3.3)
    - Download pre-built binaries from GitHub releases: https://github.com/dev7a/serverless-otlp-forwarder/releases?q=startled

## Deployment

The testbed is deployed as an AWS CloudFormation stack using the AWS SAM CLI.

1.  Navigate to the `perftest/` directory.
2.  Build the SAM application:
    ```bash
    sam build --beta-features
    ```
    *(The `--beta-features` flag is needed for `rust-cargolambda` build support, as indicated in `samconfig.toml`)*.
3.  Deploy the stack:
    ```bash
    sam deploy --guided
    ```
    Follow the prompts. You can accept the defaults specified in `samconfig.toml` (e.g., stack name `benchmark`, region `us-east-1`). Ensure you acknowledge IAM role creation capabilities.

## Running Benchmarks

Benchmarks are run using the `startled` CLI tool. For complete documentation and usage options, see the [startled documentation on crates.io](https://crates.io/crates/startled).

### Direct Usage Examples

**Test all Python functions in the stack:**
```bash
startled stack perftest -s python -c 20 -n 50 -m 256 --proxy perftest-proxy -d /tmp/perftest/results
```
This tests all Python functions with 20 concurrent invocations, 50 iterations, 256MB memory, using the proxy for accurate timing, and saves results to `/tmp/perftest/results`.

**Test all Node.js functions:**
```bash
startled stack perftest -s node -c 10 -n 100 -m 512 --proxy perftest-proxy -d /tmp/perftest/results
```

**Test a specific function:**
```bash
startled function perftest-python-lite-sync -c 10 -n 100 -m 128 --proxy perftest-proxy -d /tmp/perftest/results
```

**Generate HTML report from results:**
```bash
startled report -d /tmp/perftest/results -o /tmp/perftest/reports --readme testbed.md
```

### Automation Script

A convenience shell script (`run_benchmarks.sh`) is provided that runs all tests in sequence across different memory configurations:

```bash
# Make sure you're in the perftest directory
cd perftest/

# Run the complete benchmark suite
./run_benchmarks.sh
```

This script will:
- Test Node.js functions with 128MB, 256MB, 512MB, and 1024MB memory
- Test Python functions with 128MB, 256MB, 512MB, and 1024MB memory  
- Use 10 concurrent invocations and 100 iterations per test
- Save results to `./results/`
- Generate an HTML report in `./reports/`
- Provide colored progress output and error handling

The script runs a comprehensive test suite but does not support configuration options. For custom configurations, use the `startled` CLI directly.

### Example Workflow

#### Option 1: Using the Automation Script (Recommended)
1.  **Deploy the stack:**
    ```bash
    cd perftest/
    sam build --beta-features
    sam deploy --guided
    ```
2.  **Run complete benchmark suite:**
    ```bash
    ./run_benchmarks.sh
    ```
3.  **View results:**
    Open `reports/index.html` in your browser to view the results.

#### Option 2: Manual Commands
1.  **Deploy the stack:**
    ```bash
    cd perftest/
    sam build --beta-features
    sam deploy --guided
    ```
2.  **Run specific benchmarks:**
    ```bash
    # Test Python functions with 512MB memory
    startled stack perftest -s python -c 10 -n 100 -m 512 --proxy perftest-proxy -d ./results
    
    # Test Node.js functions with 256MB memory  
    startled stack perftest -s node -c 10 -n 100 -m 256 --proxy perftest-proxy -d ./results
    ```
3.  **Generate and view reports:**
    ```bash
    startled report -d ./results -o ./reports --readme testbed.md
    ```
    Open `reports/index.html` in your browser to view the results.

## Customization
-   **Memory Configurations**: Use the `-m` parameter to test different memory sizes (e.g., `-m 128`, `-m 512`, `-m 1024`).
-   **Concurrency/Rounds**: Adjust the `-c` (concurrency) and `-n` (iterations) parameters in your `startled` commands.
-   **Function Workload**: Modify the `process_level` function (or equivalent) within the language-specific source files in `functions/*/` to change the nature of the work being done by the Lambda functions.
-   **Collector Configuration**: Adjust the `collector.yaml` file in `functions/confmaps/` to alter how the OTel collector extensions behave (e.g., change exporters, processors, sampling). Remember to rebuild and redeploy the `CollectorConfiglLayer` (which happens automatically with `sam build` if changes are detected in `functions/confmaps/`).
-   **OTel Endpoint**: By default, collectors export to a mock API Gateway. To send data to a real observability backend, update the `OTEL_EXPORTER_OTLP_ENDPOINT` in `template.yaml` (either in `Globals` or function-specific environment variables) or directly in the collector configuration files, then redeploy the stack.

This testbed provides a flexible and robust environment for evaluating and comparing OpenTelemetry performance on AWS Lambda, with a particular focus on the trade-offs between extension-based and direct-to-stdout telemetry solutions.

## Automated Report Generation with GitHub Actions

A GitHub Actions workflow is provided (`.github/workflows/benchmark.yml`) that automatically:

1. **Generates HTML performance reports** from committed benchmark results
2. **Publishes reports to GitHub Pages** for easy viewing and sharing
3. **Updates automatically** when new results are committed

### Setting Up Automated Reports

To enable automated report generation:

1. **Run benchmarks locally** and commit results:
   ```bash
   # Deploy infrastructure and run benchmarks
   cd perftest/
   sam build --beta-features && sam deploy --guided
   ./run_benchmarks.sh
   
   # Commit the results
   git add results/
   git commit -m "Add benchmark results"
   git push
   ```

2. **Enable GitHub Pages** in your repository settings:
   - Go to Settings → Pages
   - Set source to "GitHub Actions"

3. **Reports generate automatically**:
   - **On results commit**: When you push new benchmark results to `perftest/results/`
   - **Manual**: Go to Actions tab and run "Generate Performance Report"
   - **On configuration changes**: When `testbed.md` or workflow files are modified

The workflow will publish reports to your repository's GitHub Pages site, accessible at: `https://[username].github.io/[repository-name]/`

### Benefits of This Approach

- **No AWS credentials required** in CI/CD
- **Fast report generation** (no deployment or benchmark execution)
- **Version-controlled results** for historical tracking
- **Reproducible reports** from committed data
