# Zsh Startup Benchmarks

This file tracks zsh startup time as configuration changes are made.

## Local Benchmarks

| Date | Description | Median | Average |
|------|-------------|--------|---------|
| 2025-04-28 | Add defered setups | .060s | .061s |
| 2025-04-28 | Introduce homebrew | .060s | .060s |
| 2025-04-28 | Update hist settings | .050s | .050s |
| 2025-04-28 | Initial setup | .042s | .042s |

## CI Benchmarks

| Date | PR | Description | Median | Average |
|------|-------|-------------|--------|---------|
| 2025-04-30 | #18 | feat: add platform-specific git configs | .040s | .039s |
| 2025-04-30 | #17 | fix: update PATH setting | .030s | .032s |
| 2025-04-30 | #16 | feat: add kubectl aliases and docs | .030s | .030s |
| 2025-04-28 | #12 | fix: update fzf-opt parameters | .030s | .030s |
| 2025-04-28 | #10 | feat: add mise-en-place | .030s | .030s |
| 2025-04-28 | #8 | feat: add starship and make zsh-defer a submodule | .030s | .031s |
| 2025-04-28 | #7 | feat: add minimal git module | .030s | .030s |
| 2025-04-28 | #6 | feat: add all-checks-green base workflow and dependabot | .040s | .039s |
| 2025-04-28 | #5 | feat: add brew setup and deferred loading | .030s | .031s |
| 2025-04-28 | #3 | feat: update workflow with docs | .020s | .024s |
| 2025-04-28 | #0 | Test PR Updated | .040s | .041s |

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
