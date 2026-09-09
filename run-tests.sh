#!/usr/bin/env bash
# ==============================================================================
# run-tests.sh - Test runner for PanelsPlus and manga dataset specifications
# ==============================================================================
# Usage:
#   ./run-tests.sh                  # Runs linters, Lua unit tests, and dataset specs
#   ./run-tests.sh --quick          # Runs Lua test suite directly (skips check.sh)
#   ./run-tests.sh --check-only     # Runs only code style and linter checks
#   ./run-tests.sh <spec-path>      # Runs a specific spec file
# ==============================================================================

set -e
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

print_help() {
    cat << 'EOF'
PanelsPlus Test Runner

Usage:
  ./run-tests.sh [OPTIONS] [SPEC_FILE...]

Options:
  -h, --help       Show this help message
  -q, --quick      Skip lint/format checks and run Lua tests immediately
  -c, --check-only Run only StyLua formatter and Luacheck linter
  -p, --python     Run only the Python annotator unit tests

Examples:
  ./run-tests.sh
  ./run-tests.sh --quick
  ./run-tests.sh tests/dataset-mangas/dataset/Bloom_Into_You_Vol_8/bloom_into_you_spec.lua
EOF
}

CHECK_ONLY=false
QUICK=false
PYTHON_ONLY=false
FORWARD_ARGS=()

for arg in "$@"; do
    case "$arg" in
        -h|--help)
            print_help
            exit 0
            ;;
        -c|--check-only)
            CHECK_ONLY=true
            ;;
        -q|--quick)
            QUICK=true
            ;;
        -p|--python)
            PYTHON_ONLY=true
            ;;
        *)
            FORWARD_ARGS+=("$arg")
            ;;
    esac
done

if [ "$PYTHON_ONLY" = true ]; then
    echo "==> Running Python Annotator Unit Tests..."
    python3 -m unittest tests/dataset-mangas/annotator/test_annotator.py
    exit 0
fi

if [ "$CHECK_ONLY" = true ]; then
    echo "==> Running Lint & Code Style Checks..."
    ./check.sh
    exit 0
fi

if [ "$QUICK" = false ]; then
    echo "==> [1/3] Running Code Style and Linter Checks..."
    ./check.sh
fi

if command -v python3 &>/dev/null && [ -f "tests/dataset-mangas/annotator/test_annotator.py" ]; then
    echo "==> [2/3] Running Python Annotator Tests..."
    python3 -m unittest tests/dataset-mangas/annotator/test_annotator.py
fi

echo "==> [3/3] Running Lua Test Suite & Manga Dataset Specs..."
lua tests/run_tests.lua "${FORWARD_ARGS[@]}"

echo "==> All test suites passed successfully!"
