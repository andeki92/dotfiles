#!/bin/bash

# Benchmark script for measuring zsh startup time
# Usage: ./scripts/benchmark.sh [--save]

# Configuration
NUM_TESTS=10
WARMUP_RUNS=3      # Number of warmup runs to perform before actual measurement
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

# Perform warmup runs to get more consistent results
echo "Running $WARMUP_RUNS warmup tests..."
for i in $(seq 1 $WARMUP_RUNS); do
  warmup_result=$(measure_startup)
  echo "  Warmup $i: ${warmup_result}s"
done

echo "Running $NUM_TESTS tests..."
results=()

for i in $(seq 1 $NUM_TESTS); do
  result=$(measure_startup)
  results+=($result)
  echo "  Test $i: ${result}s"
done

# Calculate median (more stable than average)
# Sort results numerically
sorted_results=($(printf "%s\n" "${results[@]}" | sort -n))
mid=$((${#sorted_results[@]} / 2))
if [ $((${#sorted_results[@]} % 2)) -eq 0 ]; then
  # Even number of elements, average the middle two
  median=$(echo "scale=3; (${sorted_results[$mid-1]} + ${sorted_results[$mid]}) / 2" | bc)
else
  # Odd number of elements, take the middle one
  median=${sorted_results[$mid]}
fi

# Calculate average for reference
total=0
for r in "${results[@]}"; do
  total=$(echo "$total + $r" | bc)
done
average=$(echo "scale=3; $total / ${#results[@]}" | bc)

# Compare with last result if available
if [[ -f "$BENCHMARK_FILE" ]]; then
  # Determine which section to compare against
  if [[ "$CI" == "true" ]]; then
    last_median=$(grep -A 10 "^## CI Benchmarks" "$BENCHMARK_FILE" | grep -m1 -oE 'Median \| [0-9]+\.[0-9]+s' | grep -oE '[0-9]+\.[0-9]+s' | tr -d 's')
  else
    last_median=$(grep -A 10 "^## Local Benchmarks" "$BENCHMARK_FILE" | grep -m1 -oE 'Median \| [0-9]+\.[0-9]+s' | grep -oE '[0-9]+\.[0-9]+s' | tr -d 's')
  fi
  
  if [[ ! -z "$last_median" ]]; then
    diff=$(echo "scale=3; $last_median - $median" | bc)
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
echo "  Median startup time: ${median}s"
echo "  Average startup time: ${average}s"
if [[ ! -z "$comparison" ]]; then
  echo "  Compared to last: $comparison"
fi

# If running in CI, save PR time for GitHub Actions
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
    # Get PR number from GitHub environment
    PR_NUMBER=${PR_NUMBER:-"N/A"}
    description=${PR_DESCRIPTION:-"CI Run"}
    echo "Using PR #${PR_NUMBER} with description: ${description}"
    
    entry="| ${current_date} | #${PR_NUMBER} | ${description} | ${median}s | ${average}s |"
    
    # Check if an entry for this PR already exists
    if grep -q "#${PR_NUMBER}" "$BENCHMARK_FILE"; then
      echo "Updating existing entry for PR #${PR_NUMBER}"
      # Use awk to replace the existing line with the new entry
      # This is more portable than sed across different platforms
      awk -v pr="#${PR_NUMBER}" -v new_entry="$entry" '
        $0 ~ pr {print new_entry; next}
        {print}
      ' "$BENCHMARK_FILE" > "$BENCHMARK_FILE.tmp"
      mv "$BENCHMARK_FILE.tmp" "$BENCHMARK_FILE"
    else
      echo "Adding new entry for PR #${PR_NUMBER}"
      # Find the CI section line number
      ci_line=$(grep -n "^## CI Benchmarks" "$BENCHMARK_FILE" | cut -d: -f1)
      header_line=$((ci_line + 3))  # Headers are 3 lines after section title
      
      # Insert after header line
      head -n $header_line "$BENCHMARK_FILE" > "$BENCHMARK_FILE.tmp"
      echo "$entry" >> "$BENCHMARK_FILE.tmp"
      tail -n +$((header_line + 1)) "$BENCHMARK_FILE" >> "$BENCHMARK_FILE.tmp"
      mv "$BENCHMARK_FILE.tmp" "$BENCHMARK_FILE"
    fi
  else
    read -p "Enter a description for this benchmark: " description
    entry="| ${current_date} | ${description} | ${median}s | ${average}s |"
    
    # Find the Local section line number
    local_line=$(grep -n "^## Local Benchmarks" "$BENCHMARK_FILE" | cut -d: -f1)
    header_line=$((local_line + 3))  # Headers are 3 lines after section title
    
    # Insert after header line
    head -n $header_line "$BENCHMARK_FILE" > "$BENCHMARK_FILE.tmp"
    echo "$entry" >> "$BENCHMARK_FILE.tmp"
    tail -n +$((header_line + 1)) "$BENCHMARK_FILE" >> "$BENCHMARK_FILE.tmp"
    mv "$BENCHMARK_FILE.tmp" "$BENCHMARK_FILE"
  fi
  
  echo "Results saved! ✓"
fi

exit 0 