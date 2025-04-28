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

# Save PR time for GitHub Actions
if [[ "$CI" == "true" ]]; then
  echo "PR_TIME=${average}" > /tmp/pr_time.txt
fi

# Save results if requested
if [[ "$SAVE_RESULTS" == "true" ]]; then
  echo
  echo "💾 Saving results to $BENCHMARK_FILE"
  
  # Get the current date
  current_date=$(date +%Y-%m-%d)
  
  # Get description
  if [[ "$CI" == "true" ]]; then
    # Get PR number and description from environment variables
    PR_NUMBER=${PR_NUMBER:-"N/A"}
    description=${PR_DESCRIPTION:-"CI Run"}
    echo "Using PR #${PR_NUMBER} with description: ${description}"
    
    entry="| ${current_date} | #${PR_NUMBER} | ${description} | ${average}s |"
    
    # First check if an entry for this PR already exists
    existing_line=$(grep -n "\| #${PR_NUMBER} \|" "$BENCHMARK_FILE" | cut -d: -f1)
    
    if [[ -n "$existing_line" ]]; then
      echo "Found existing entry for PR #${PR_NUMBER} at line ${existing_line}, updating it"
      # Replace the existing line with the new entry
      # Use platform-independent approach for sed
      awk -v line="$existing_line" -v new_entry="$entry" 'NR==line {print new_entry; next} {print}' "$BENCHMARK_FILE" > "$BENCHMARK_FILE.tmp"
      mv "$BENCHMARK_FILE.tmp" "$BENCHMARK_FILE"
    else
      echo "No existing entry found for PR #${PR_NUMBER}, adding new entry"
      # Find the CI section line number
      ci_line=$(grep -n "^## CI Benchmarks" "$BENCHMARK_FILE" | cut -d: -f1)
      header_line=$((ci_line + 3))  # Headers are 3 lines after section title
      
      # Insert after header line
      head -n $header_line "$BENCHMARK_FILE" > "$BENCHMARK_FILE.tmp"
      echo "$entry" >> "$BENCHMARK_FILE.tmp"
      tail -n +$((header_line + 1)) "$BENCHMARK_FILE" >> "$BENCHMARK_FILE.tmp"
      
      # Replace original with new file
      mv "$BENCHMARK_FILE.tmp" "$BENCHMARK_FILE"
    fi
  else
    read -p "Enter a description for this benchmark: " description
    entry="| ${current_date} | ${description} | ${average}s |"
    
    # Find the Local section line number
    local_line=$(grep -n "^## Local Benchmarks" "$BENCHMARK_FILE" | cut -d: -f1)
    header_line=$((local_line + 3))  # Headers are 3 lines after section title
    
    # Insert after header line
    head -n $header_line "$BENCHMARK_FILE" > "$BENCHMARK_FILE.tmp"
    echo "$entry" >> "$BENCHMARK_FILE.tmp"
    tail -n +$((header_line + 1)) "$BENCHMARK_FILE" >> "$BENCHMARK_FILE.tmp"
    
    # Replace original with new file
    mv "$BENCHMARK_FILE.tmp" "$BENCHMARK_FILE"
  fi
  
  echo "Results saved! ✓"
fi

exit 0 