# Zsh Startup Benchmarks

This file tracks zsh startup time as configuration changes are made.

## Local Benchmarks

| Date | Description | Median | Average |
|------|-------------|--------|---------|
| 2025-04-28 | Update hist settings | .050s | .050s |
| 2025-04-28 | Initial setup | .042s | .042s |

## CI Benchmarks

| Date | PR | Description | Median | Average |
|------|-------|-------------|--------|---------|
| | | | | |

## Methodology

Benchmarks are performed using the `scripts/benchmark.sh` script which:

1. Runs zsh with the `-i` flag to load as a login shell
2. Performs several warmup runs to eliminate cold cache effects
3. Executes multiple tests to calculate median and average values
4. Records results in this file when run with the `--save` option

To run benchmarks:

```bash
# Run a benchmark
./scripts/benchmark.sh

# Run and save the results
./scripts/benchmark.sh --save
``` 
