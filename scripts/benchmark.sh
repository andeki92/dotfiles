#!/bin/bash

# Benchmark script for measuring zsh startup time
# Usage: ./scripts/benchmark.sh [--save]

# Configuration
NUM_TESTS=5
BENCHMARK_FILE="docs/benchmarks.md"
SAVE_RESULTS=false

# Parse arguments
if [[ "$1" == "--save" ]]; then
  SAVE_RESULTS=true
fi

# Detect environment
CI=${CI:-false}
if [[ -n "$GITHUB_ACTIONS" || -n "$GITLAB_CI" || -n "$TRAVIS" || -n "$CIRCLECI" ]]; then
  CI=true
fi

# Function to measure startup time
measure_startup() {
  /usr/bin/time -p zsh -i -c exit 2>&1 | grep real | awk '{print $2}'
}

# Run tests
echo "⏱️  Measuring zsh startup time"
echo "==========================="
if [[ "$CI" == "true" ]]; then
  echo "Environment: CI"
else
  echo "Environment: Local"
fi
echo "Running $NUM_TESTS tests..."

total_time=0
results=()

for i in $(seq 1 $NUM_TESTS); do
  result=$(measure_startup)
  results+=($result)
  total_time=$(echo "$total_time + $result" | bc)
  echo "  Test $i: ${result}s"
done

# Calculate average
average=$(echo "scale=3; $total_time / $NUM_TESTS" | bc)

# Compare with last result if available
if [[ -f "$BENCHMARK_FILE" ]]; then
  # Determine which section to compare against
  if [[ "$CI" == "true" ]]; then
    last_result=$(grep -A 10 "^## CI Benchmarks" "$BENCHMARK_FILE" | grep -oE '[0-9]+\.[0-9]+s' | tail -1 | tr -d 's')
  else
    last_result=$(grep -A 10 "^## Local Benchmarks" "$BENCHMARK_FILE" | grep -oE '[0-9]+\.[0-9]+s' | tail -1 | tr -d 's')
  fi
  
  if [[ ! -z "$last_result" ]]; then
    diff=$(echo "scale=3; $last_result - $average" | bc)
    if (( $(echo "$diff > 0" | bc -l) )); then
      comparison="${diff}s faster ✅"
    elif (( $(echo "$diff < 0" | bc -l) )); then
      diff=$(echo "scale=3; $diff * -1" | bc)
      comparison="${diff}s slower ❌"
    else
      comparison="no change ⚠️"
    fi
  fi
fi

# Display results
echo
echo "🔍 Results:"
echo "  Date: $(date +%Y-%m-%d)"
echo "  Average startup time: ${average}s"
if [[ ! -z "$comparison" ]]; then
  echo "  Compared to last: $comparison"
fi

# Save results if requested
if [[ "$SAVE_RESULTS" == "true" ]]; then
  echo
  echo "💾 Saving results to $BENCHMARK_FILE"
  
  if [[ "$CI" == "true" ]]; then
    # Get PR number from GitHub environment
    PR_NUMBER=${GITHUB_REF#refs/pull/}
    PR_NUMBER=${PR_NUMBER%/merge}
    
    # Use automated description in CI
    description="CI Run"
    
    # Format for insertion into markdown table
    entry="| $(date +%Y-%m-%d) | #${PR_NUMBER:-N/A} | $description | ${average}s |"
    
    # Insert into CI section of benchmark file
    awk -v entry="$entry" '
      /\| +\| +\| +\|/ {
        if (NF == 0) {
          print entry
        } else {
          print entry
          next
        }
      }
      { print }
    ' "$BENCHMARK_FILE" > "${BENCHMARK_FILE}.tmp"
  else
    # Get description from user for local benchmark
    read -p "Enter a description for this benchmark: " description
    
    # Format for insertion into markdown table
    entry="| $(date +%Y-%m-%d) | $description | ${average}s |"
    
    # Insert into local section of benchmark file
    awk -v entry="$entry" '
      /\| +\| +Minimal baseline configuration/ {
        if (NF == 0) {
          print entry
        } else {
          print entry
          next
        }
      }
      { print }
    ' "$BENCHMARK_FILE" > "${BENCHMARK_FILE}.tmp"
  fi
  
  mv "${BENCHMARK_FILE}.tmp" "$BENCHMARK_FILE"
  
  echo "Results saved! ✓"
fi

exit 0 