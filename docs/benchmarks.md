# Zsh Startup Benchmarks

This file tracks zsh startup time as configuration changes are made.

## Local Benchmarks

| Date | Description | Time |
|------|-------------|------|
| 2025-04-28 | Initial setup | .042s |

## CI Benchmarks

| Date | PR | Description | Time |
|------|-------|-------------|------|
| | | | |

## Methodology

Benchmarks are performed using the `scripts/benchmark.sh` script which:

1. Runs zsh with the `-i` flag to load as a login shell
2. Executes multiple tests to calculate an average
3. Records results in this file when run with the `--save` option

To run benchmarks:

```bash
# Run a benchmark
./scripts/benchmark.sh

# Run and save the results
./scripts/benchmark.sh --save
``` 
