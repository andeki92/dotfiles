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

# Save PR time for GitHub Actions
if [[ "$CI" == "true" ]]; then
  echo "PR_TIME=${median}" > /tmp/pr_time.txt
fi

# Ensure benchmark file exists with proper structure
ensure_benchmark_file() {
  if [[ ! -f "$BENCHMARK_FILE" ]]; then
    echo "Creating new benchmark file at $BENCHMARK_FILE"
    mkdir -p "$(dirname "$BENCHMARK_FILE")"
    
    cat > "$BENCHMARK_FILE" << EOF
# Zsh Startup Benchmarks

## CI Benchmarks

| Date | PR | Description | Median | Average |
|------|----|----|--------|--------|

## Local Benchmarks

| Date | Description | Median | Average |
|------|------------|--------|--------|
EOF
  else
    # Check if file has the right sections, add them if missing
    if ! grep -q "^## CI Benchmarks" "$BENCHMARK_FILE"; then
      echo -e "\n## CI Benchmarks\n\n| Date | PR | Description | Median | Average |\n|------|----|----|--------|--------|" >> "$BENCHMARK_FILE"
    fi
    
    if ! grep -q "^## Local Benchmarks" "$BENCHMARK_FILE"; then
      echo -e "\n## Local Benchmarks\n\n| Date | Description | Median | Average |\n|------|------------|--------|--------|" >> "$BENCHMARK_FILE"
    fi
  fi
}

# Save results if requested
if [[ "$SAVE_RESULTS" == "true" ]]; then
  echo
  echo "💾 Saving results to $BENCHMARK_FILE"
  
  # Ensure benchmark file exists with proper structure
  ensure_benchmark_file
  
  # Get the current date
  current_date=$(date +%Y-%m-%d)
  
  # Get description
  if [[ "$CI" == "true" ]]; then
    # Get PR number from GitHub environment
    PR_NUMBER=${PR_NUMBER:-"N/A"}
    description=${PR_DESCRIPTION:-"CI Run"}
    echo "Using PR #${PR_NUMBER} with description: ${description}"
    
    entry="| ${current_date} | #${PR_NUMBER} | ${description} | ${median}s | ${average}s |"
    
    # First check if an entry for this PR already exists (more flexible pattern matching)
    if [[ "$PR_NUMBER" != "N/A" ]]; then
      # Look for an existing line with this PR number (allowing for different formatting)
      existing_line=$(grep -n "#${PR_NUMBER}[[:space:]]*|" "$BENCHMARK_FILE" | cut -d: -f1)
      
      # If not found with the above pattern, try an alternative
      if [[ -z "$existing_line" ]]; then
        existing_line=$(grep -n "|[[:space:]]*#${PR_NUMBER}" "$BENCHMARK_FILE" | cut -d: -f1)
      fi
      
      if [[ -n "$existing_line" ]]; then
        echo "Found existing entry for PR #${PR_NUMBER} at line ${existing_line}, updating it"
        # Replace the existing line with the new entry using awk (platform independent)
        awk -v line="$existing_line" -v new_entry="$entry" 'NR==line {print new_entry; next} {print}' "$BENCHMARK_FILE" > "$BENCHMARK_FILE.tmp"
        mv "$BENCHMARK_FILE.tmp" "$BENCHMARK_FILE"
        echo "Updated existing entry ✓"
      else
        echo "No existing entry found for PR #${PR_NUMBER}, adding new entry"
        # Find the CI section line number
        ci_line=$(grep -n "^## CI Benchmarks" "$BENCHMARK_FILE" | cut -d: -f1)
        if [[ -n "$ci_line" ]]; then
          # Find the headers line
          headers_line=$(tail -n +$ci_line "$BENCHMARK_FILE" | grep -n "^\|.*\|.*\|" | head -1 | cut -d: -f1)
          if [[ -n "$headers_line" ]]; then
            # Calculate the actual line number in the file
            actual_header_line=$((ci_line + headers_line - 1))
            # Insert the entry right after the header line
            awk -v line="$actual_header_line" -v new_entry="$entry" 'NR==line {print; print new_entry; next} {print}' "$BENCHMARK_FILE" > "$BENCHMARK_FILE.tmp"
            mv "$BENCHMARK_FILE.tmp" "$BENCHMARK_FILE"
            echo "Added new entry ✓"
          else
            echo "Error: Could not find headers in CI Benchmarks section"
            exit 1
          fi
        else
          echo "Error: CI Benchmarks section not found in $BENCHMARK_FILE"
          exit 1
        fi
      fi
    else
      echo "Warning: No PR number provided, adding generic entry"
      ci_line=$(grep -n "^## CI Benchmarks" "$BENCHMARK_FILE" | cut -d: -f1)
      headers_line=$(tail -n +$ci_line "$BENCHMARK_FILE" | grep -n "^\|.*\|.*\|" | head -1 | cut -d: -f1)
      actual_header_line=$((ci_line + headers_line - 1))
      awk -v line="$actual_header_line" -v new_entry="$entry" 'NR==line {print; print new_entry; next} {print}' "$BENCHMARK_FILE" > "$BENCHMARK_FILE.tmp"
      mv "$BENCHMARK_FILE.tmp" "$BENCHMARK_FILE"
    fi
  else
    # Local benchmark
    read -p "Enter a description for this benchmark: " description
    entry="| ${current_date} | ${description} | ${median}s | ${average}s |"
    
    # Find the Local section line number
    local_line=$(grep -n "^## Local Benchmarks" "$BENCHMARK_FILE" | cut -d: -f1)
    if [[ -n "$local_line" ]]; then
      # Find the headers line
      headers_line=$(tail -n +$local_line "$BENCHMARK_FILE" | grep -n "^\|.*\|.*\|" | head -1 | cut -d: -f1)
      if [[ -n "$headers_line" ]]; then
        # Calculate the actual line number in the file
        actual_header_line=$((local_line + headers_line - 1))
        # Insert the entry right after the header line
        awk -v line="$actual_header_line" -v new_entry="$entry" 'NR==line {print; print new_entry; next} {print}' "$BENCHMARK_FILE" > "$BENCHMARK_FILE.tmp"
        mv "$BENCHMARK_FILE.tmp" "$BENCHMARK_FILE"
      else
        echo "Error: Could not find headers in Local Benchmarks section"
        exit 1
      fi
    else
      echo "Error: Local Benchmarks section not found in $BENCHMARK_FILE"
      exit 1
    fi
  fi
  
  echo "Results saved! ✓"
fi

# Write output to a file for GitHub Actions to parse
if [[ "$CI" == "true" ]]; then
  {
    echo "🔍 Results:"
    echo "  Date: $(date +%Y-%m-%d)"
    echo "  Median startup time: ${median}s"
    echo "  Average startup time: ${average}s"
    if [[ ! -z "$comparison" ]]; then
      echo "  Compared to last: $comparison"
    fi
  } > /tmp/output.txt
fi

exit 0 