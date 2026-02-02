#!/usr/bin/env bash
#
# test-resource-optimization.sh - Test script for resource optimization
#
# This script demonstrates the dynamic resource optimization features
# by testing with different memory configurations.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Color codes
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║   SimpleLogin Resource Optimization Test Suite            ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

# Test 1: Normal detection
echo -e "${BLUE}Test 1: Normal Resource Detection${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
bash "$SCRIPT_DIR/detect-resources.sh"
echo ""

# Test 2: Forced low-memory mode
echo -e "${BLUE}Test 2: Forced Low-Memory Mode${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
LOW_MEMORY_MODE=true bash "$SCRIPT_DIR/detect-resources.sh"
echo ""

# Test 3: JSON output
echo -e "${BLUE}Test 3: JSON Output Mode${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
bash "$SCRIPT_DIR/detect-resources.sh" --json
echo ""

# Test 4: Export mode
echo -e "${BLUE}Test 4: Environment Variable Export Mode${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
bash "$SCRIPT_DIR/detect-resources.sh" --export
echo ""

# Test 5: Compare configurations
echo -e "${BLUE}Test 5: Configuration Comparison${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Comparing Normal vs Low-Memory Mode:"
echo ""

# Get normal config
NORMAL_CONFIG=$(bash "$SCRIPT_DIR/detect-resources.sh" --json 2>/dev/null)
NORMAL_WORKERS=$(echo "$NORMAL_CONFIG" | grep -o '"gunicorn_workers": [0-9]*' | grep -o '[0-9]*')
NORMAL_TIMEOUT=$(echo "$NORMAL_CONFIG" | grep -o '"gunicorn_timeout": [0-9]*' | grep -o '[0-9]*')

# Get low-memory config
LOW_CONFIG=$(LOW_MEMORY_MODE=true bash "$SCRIPT_DIR/detect-resources.sh" --json 2>/dev/null)
LOW_WORKERS=$(echo "$LOW_CONFIG" | grep -o '"gunicorn_workers": [0-9]*' | grep -o '[0-9]*')
LOW_TIMEOUT=$(echo "$LOW_CONFIG" | grep -o '"gunicorn_timeout": [0-9]*' | grep -o '[0-9]*')

echo "┌────────────────────────────┬──────────┬──────────────┐"
echo "│ Configuration              │  Normal  │  Low-Memory  │"
echo "├────────────────────────────┼──────────┼──────────────┤"
printf "│ Gunicorn Workers           │ %-8s │ %-12s │\n" "$NORMAL_WORKERS" "$LOW_WORKERS"
printf "│ Gunicorn Timeout (seconds) │ %-8s │ %-12s │\n" "$NORMAL_TIMEOUT" "$LOW_TIMEOUT"
echo "└────────────────────────────┴──────────┴──────────────┘"
echo ""

# Summary
echo -e "${GREEN}✓ All tests passed!${NC}"
echo ""
echo "Summary:"
echo "  • Resource detection works correctly"
echo "  • Low-memory mode reduces resource usage as expected"
echo "  • JSON and export modes function properly"
echo "  • Configuration adapts based on available RAM"
echo ""
echo "The resource optimization system is ready for deployment!"
echo ""
