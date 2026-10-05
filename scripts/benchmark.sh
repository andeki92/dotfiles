#!/usr/bin/env bash

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

# Function to measure startup time
# Uses bash's `time` keyword for millisecond resolution; `/usr/bin/time -p`
# only reports hundredths, which turns sub-10ms noise into 25-33% swings.
measure_startup() {
  local TIMEFORMAT=%3R
  { time zsh -i -c exit >/dev/null 2>&1; } 2>&1
}

# Run tests
echo "⏱️  Measuring zsh startup time"
echo "==========================="

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
  results+=("$result")
  echo "  Test $i: ${result}s"
done

# Calculate median (more stable than average)
# Sort results numerically
sorted_results=()
while read -r r; do sorted_results+=("$r"); done < <(printf "%s\n" "${results[@]}" | sort -n)
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

# Compare with last saved result if available
if [[ -f "$BENCHMARK_FILE" ]]; then
  last_median=$(grep -m1 -oE '\| [0-9]*\.[0-9]+s \|' "$BENCHMARK_FILE" | grep -oE '[0-9]*\.[0-9]+')

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

# Save results if requested
if [[ "$SAVE_RESULTS" == "true" ]]; then
  echo
  echo "💾 Saving results to $BENCHMARK_FILE"

  read -r -p "Enter a description for this benchmark: " description
  entry="| $(date +%Y-%m-%d) | ${description} | ${median}s | ${average}s |"

  # Insert the new entry as the first row of the results table
  header_line=$(grep -n "^|------" "$BENCHMARK_FILE" | head -1 | cut -d: -f1)
  head -n "$header_line" "$BENCHMARK_FILE" > "$BENCHMARK_FILE.tmp"
  echo "$entry" >> "$BENCHMARK_FILE.tmp"
  tail -n +$((header_line + 1)) "$BENCHMARK_FILE" >> "$BENCHMARK_FILE.tmp"
  mv "$BENCHMARK_FILE.tmp" "$BENCHMARK_FILE"

  echo "Results saved! ✓"
fi

exit 0
