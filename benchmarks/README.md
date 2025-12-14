# GRC Benchmarks

This directory contains benchmarking scripts for testing grc/grcat performance.

## Prerequisites

Install hyperfine:
```bash
sudo apt-get install hyperfine
# or
cargo install hyperfine
```

## Running Benchmarks

1. Generate test data (only needs to be done once):
```bash
./generate-test-data.sh
```

2. Run benchmarks:
```bash
./run-benchmarks.sh
```

## What Gets Generated

The scripts generate the following (all git-ignored):
- `test-data/` - Sample command outputs (ls, ping, ps, docker, logs, etc.)
- `results-*.md` - Markdown tables with benchmark results
- `results-*.log` - Full benchmark output logs
- `comparison/` - Directory for storing comparison results

## Benchmark Categories

1. **Processing different file sizes** - Tests grcat with small, medium, and large inputs
2. **Different config file patterns** - Tests various config files (diff, docker, etc.)
3. **Overhead measurement** - Compares grcat vs plain cat
4. **Full grc wrapper** - Tests the complete grc command wrapper
5. **Startup time** - Measures grcat initialization overhead

## Results

See `BENCHMARK_RESULTS.md` for detailed performance analysis and comparison between versions.
