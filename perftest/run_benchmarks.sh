#!/bin/bash

set -e  # Exit on any error

# Configuration
STACK_NAME="perftest"
PROXY_NAME="perftest-proxy" 
RESULT_DIR="./results"
CONCURRENCY=10
ITERATIONS=100

# Memory configurations to test
MEMORY_CONFIGS=(128 256 512 1024)

# Runtimes to test (in order)
RUNTIMES=("node" "python")

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
RESET='\033[0m'

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${RESET} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${RESET} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${RESET} $1"
}

print_section() {
    echo -e "${BLUE}[SECTION]${RESET} $1"
}

# Check if startled is installed
check_prerequisites() {
    print_status "Checking prerequisites..."
    
    if ! command -v startled &> /dev/null; then
        print_error "startled CLI is not installed. Please install it first:"
        print_error "  cargo install startled --version 0.3.3"
        exit 1
    fi
    
    print_status "Prerequisites check passed ✓"
}

# Create results directory
setup_directories() {
    print_status "Setting up directories..."
    mkdir -p "$RESULT_DIR"
    print_status "Results will be saved to: $RESULT_DIR"
}

# Run benchmark for a specific runtime and memory configuration
run_benchmark() {
    local runtime=$1
    local memory=$2
    
    print_status "Running benchmark: ${runtime} runtime with ${memory}MB memory"
    print_status "  Concurrency: $CONCURRENCY"
    print_status "  Iterations: $ITERATIONS"
    print_status "  Stack: $STACK_NAME"
    print_status "  Proxy: $PROXY_NAME"
    
    startled stack "$STACK_NAME" \
        -s "$runtime" \
        -c "$CONCURRENCY" \
        -n "$ITERATIONS" \
        -m "$memory" \
        --proxy "$PROXY_NAME" \
        -d "$RESULT_DIR" \
        --parallel
    
    if [ $? -eq 0 ]; then
        print_status "✓ Completed: ${runtime} ${memory}MB"
    else
        print_error "✗ Failed: ${runtime} ${memory}MB"
        exit 1
    fi
}

# Generate report after all benchmarks
generate_report() {
    print_section "Generating HTML report..."
    
    local report_dir="/tmp/perftest/reports"
    mkdir -p "$report_dir"
    
    startled report \
        -d "$RESULT_DIR" \
        -o "$report_dir" \
        --readme testbed.md
    
    if [ $? -eq 0 ]; then
        print_status "✓ Report generated successfully"
        print_status "Open ${report_dir}/index.html in your browser to view results"
    else
        print_error "✗ Failed to generate report"
        exit 1
    fi
}

# Main execution
main() {
    print_section "Starting OpenTelemetry Lambda Performance Benchmarks"
    print_status "Configuration: ${#MEMORY_CONFIGS[@]} memory sizes × ${#RUNTIMES[@]} runtimes = $((${#MEMORY_CONFIGS[@]} * ${#RUNTIMES[@]})) total benchmark runs"
    
    check_prerequisites
    setup_directories
    
    local total_runs=0
    local completed_runs=0
    total_runs=$((${#MEMORY_CONFIGS[@]} * ${#RUNTIMES[@]}))
    
    # Run benchmarks for each runtime and memory configuration
    for runtime in "${RUNTIMES[@]}"; do
        print_section "Testing ${runtime} runtime"
        
        for memory in "${MEMORY_CONFIGS[@]}"; do
            completed_runs=$((completed_runs + 1))
            print_status "Progress: ${completed_runs}/${total_runs}"
            
            run_benchmark "$runtime" "$memory"
            
            # Brief pause between tests
            sleep 2
        done
        
        print_status "✓ Completed all ${runtime} runtime tests"
    done
    
    print_section "All benchmarks completed successfully!"
    generate_report
    
    print_section "Benchmark Summary"
    print_status "Total benchmark runs: $total_runs"
    print_status "Results directory: $RESULT_DIR"
    print_status "Reports directory: /tmp/perftest/reports"
    print_status ""
    print_status "To commit results for GitHub Pages:"
    print_status "  git add results/ && git commit -m 'Add benchmark results'"
    print_status "Done! 🎉"
}

# Handle Ctrl+C gracefully
trap 'print_warning "Benchmark interrupted by user"; exit 130' INT

# Run main function
main "$@" 