#!/bin/bash
# Benchmark grc/grcat performance improvements
set -e

BENCH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA_DIR="${BENCH_DIR}/test-data"
DOTFILES_DIR="${BENCH_DIR}/.."

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== GRC Performance Benchmarks ===${NC}\n"

# Check if test data exists
if [ ! -d "${DATA_DIR}" ]; then
    echo "Generating test data..."
    bash "${BENCH_DIR}/generate-test-data.sh"
fi

# Check if hyperfine is installed
if ! command -v hyperfine &> /dev/null; then
    echo -e "${YELLOW}Error: hyperfine is not installed.${NC}"
    echo "Install it with: sudo apt-get install hyperfine"
    echo "Or visit: https://github.com/sharkdp/hyperfine"
    exit 1
fi

echo -e "${GREEN}Running benchmarks...${NC}\n"

# Benchmark 1: grcat with different input sizes
echo -e "${BLUE}Benchmark 1: Processing different file sizes${NC}"
hyperfine --warmup 3 \
    --export-markdown "${BENCH_DIR}/results-filesize.md" \
    "cat ${DATA_DIR}/ping-output.txt | ${DOTFILES_DIR}/bin/grcat ${DOTFILES_DIR}/grc/conf.ping" \
    "cat ${DATA_DIR}/ps-output.txt | ${DOTFILES_DIR}/bin/grcat ${DOTFILES_DIR}/grc/conf.ps" \
    "cat ${DATA_DIR}/large-log.txt | ${DOTFILES_DIR}/bin/grcat ${DOTFILES_DIR}/grc/conf.log"

echo ""

# Benchmark 2: grcat with different config files
echo -e "${BLUE}Benchmark 2: Different config file patterns${NC}"
hyperfine --warmup 3 \
    --export-markdown "${BENCH_DIR}/results-configs.md" \
    "cat ${DATA_DIR}/diff-output.txt | ${DOTFILES_DIR}/bin/grcat ${DOTFILES_DIR}/grc/conf.diff" \
    "cat ${DATA_DIR}/docker-ps-output.txt | ${DOTFILES_DIR}/bin/grcat ${DOTFILES_DIR}/grc/conf.dockerps"

echo ""

# Benchmark 3: Comparing grcat vs plain cat (overhead measurement)
echo -e "${BLUE}Benchmark 3: grcat overhead vs plain cat${NC}"
hyperfine --warmup 3 \
    --export-markdown "${BENCH_DIR}/results-overhead.md" \
    "cat ${DATA_DIR}/large-log.txt" \
    "cat ${DATA_DIR}/large-log.txt | ${DOTFILES_DIR}/bin/grcat ${DOTFILES_DIR}/grc/conf.log"

echo ""

# Benchmark 4: Full grc wrapper
echo -e "${BLUE}Benchmark 4: Full grc wrapper performance${NC}"
hyperfine --warmup 3 \
    --export-markdown "${BENCH_DIR}/results-wrapper.md" \
    "${DOTFILES_DIR}/bin/grc -c ${DOTFILES_DIR}/grc/conf.ps ps aux"

echo ""

# Benchmark 5: grcat startup time (important for ZLE hook responsiveness)
echo -e "${BLUE}Benchmark 5: grcat startup time (empty input)${NC}"
hyperfine --warmup 10 \
    --export-markdown "${BENCH_DIR}/results-startup.md" \
    "echo '' | ${DOTFILES_DIR}/bin/grcat ${DOTFILES_DIR}/grc/conf.log"

echo ""

echo -e "${GREEN}=== Benchmarks Complete ===${NC}\n"
echo "Results saved to:"
echo "  - ${BENCH_DIR}/results-filesize.md"
echo "  - ${BENCH_DIR}/results-configs.md"
echo "  - ${BENCH_DIR}/results-overhead.md"
echo "  - ${BENCH_DIR}/results-wrapper.md"
echo "  - ${BENCH_DIR}/results-startup.md"
echo ""
echo -e "${YELLOW}To compare with the original version:${NC}"
echo "  1. Checkout master: git stash && git checkout master"
echo "  2. Run: bash benchmarks/run-benchmarks.sh"
echo "  3. Save results to a different location"
echo "  4. Checkout this branch: git checkout grc-uplift-2025"
echo "  5. Run benchmarks again and compare"
