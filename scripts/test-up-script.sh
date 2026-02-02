#!/usr/bin/env bash
#
# test-up-script.sh - Test up.sh script flag functionality
#
# This script tests that up.sh correctly handles the -f flag for foreground mode
# and runs in detached mode by default.
#
# Note: This test validates the command construction logic without actually
# running docker compose, which would require a full environment setup.

set -uo pipefail

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

TEST_PASSED=0
TEST_FAILED=0

log_test() {
  echo -e "${BLUE}[TEST]${NC} $*"
}

log_pass() {
  echo -e "${GREEN}[PASS]${NC} $*"
  ((TEST_PASSED++))
}

log_fail() {
  echo -e "${RED}[FAIL]${NC} $*"
  ((TEST_FAILED++))
}

log_info() {
  echo -e "${YELLOW}[INFO]${NC} $*"
}

# Test 1: Verify script has -f flag option
test_foreground_flag_exists() {
  log_test "Checking if up.sh contains foreground flag option..."
  
  if grep -q "FOREGROUND_MODE" up.sh; then
    log_pass "FOREGROUND_MODE variable found in up.sh"
  else
    log_fail "FOREGROUND_MODE variable not found in up.sh"
    return 1
  fi
  
  if grep -q 'getopts.*f' up.sh; then
    log_pass "Flag parsing for -f option found in up.sh"
  else
    log_fail "Flag parsing for -f option not found in up.sh"
    return 1
  fi
}

# Test 2: Verify usage help exists
test_usage_help_exists() {
  log_test "Checking if up.sh has usage help..."
  
  if grep -q "show_usage" up.sh; then
    log_pass "show_usage function found in up.sh"
  else
    log_fail "show_usage function not found in up.sh"
    return 1
  fi
  
  if grep -q "\-h.*Show this help" up.sh; then
    log_pass "Help option documentation found in up.sh"
  else
    log_fail "Help option documentation not found in up.sh"
    return 1
  fi
}

# Test 3: Verify conditional docker compose logic
test_conditional_docker_compose() {
  log_test "Checking if up.sh has conditional docker compose logic..."
  
  if grep -q 'if.*FOREGROUND_MODE.*true' up.sh; then
    log_pass "Conditional check for FOREGROUND_MODE found in up.sh"
  else
    log_fail "Conditional check for FOREGROUND_MODE not found in up.sh"
    return 1
  fi
  
  # Check for foreground mode command (without --detach)
  if grep -q 'docker compose up --remove-orphans \$@' up.sh && \
     ! grep -A1 'FOREGROUND_MODE.*true' up.sh | grep -q 'detach'; then
    log_pass "Foreground mode docker compose command found (without --detach)"
  else
    log_fail "Foreground mode docker compose command not properly configured"
    return 1
  fi
  
  # Check for detached mode command (with --detach)
  if grep -q 'docker compose up --remove-orphans --detach \$@' up.sh; then
    log_pass "Detached mode docker compose command found (with --detach)"
  else
    log_fail "Detached mode docker compose command not found"
    return 1
  fi
}

# Test 4: Test help flag output
test_help_flag() {
  log_test "Testing -h help flag output..."
  
  # Run up.sh with -h flag and capture output
  if output=$(./up.sh -h 2>&1); then
    if echo "$output" | grep -q "Usage:"; then
      log_pass "Help output contains usage information"
    else
      log_fail "Help output does not contain usage information"
      return 1
    fi
    
    if echo "$output" | grep -q "\-f"; then
      log_pass "Help output documents the -f flag"
    else
      log_fail "Help output does not document the -f flag"
      return 1
    fi
  else
    log_fail "Failed to run up.sh -h"
    return 1
  fi
}

# Test 5: Verify default behavior (no flag) would use detached mode
test_default_detached_mode() {
  log_test "Verifying default behavior uses detached mode..."
  
  # Check that FOREGROUND_MODE defaults to false
  if grep -q "FOREGROUND_MODE=false" up.sh; then
    log_pass "FOREGROUND_MODE defaults to false (detached mode)"
  else
    log_fail "FOREGROUND_MODE does not default to false"
    return 1
  fi
}

# Test 6: Verify invalid flag handling
test_invalid_flag() {
  log_test "Testing invalid flag handling..."
  
  # Run up.sh with invalid flag
  if output=$(./up.sh -x 2>&1); then
    log_fail "Script should exit with error for invalid flag"
    return 1
  else
    if echo "$output" | grep -qi "invalid"; then
      log_pass "Script properly rejects invalid flags"
    else
      log_fail "Script does not properly handle invalid flags"
      return 1
    fi
  fi
}

# Main test execution
main() {
  echo "=========================================="
  echo "Testing up.sh Flag Functionality"
  echo "=========================================="
  echo ""
  
  # Change to repository root
  cd "$(dirname "$0")/.." || exit 1
  
  log_info "Working directory: $(pwd)"
  log_info "Testing up.sh script..."
  echo ""
  
  # Run all tests
  test_foreground_flag_exists
  echo ""
  test_usage_help_exists
  echo ""
  test_conditional_docker_compose
  echo ""
  test_help_flag
  echo ""
  test_default_detached_mode
  echo ""
  test_invalid_flag
  echo ""
  
  # Summary
  echo "=========================================="
  echo "Test Summary"
  echo "=========================================="
  echo -e "${GREEN}Passed: $TEST_PASSED${NC}"
  echo -e "${RED}Failed: $TEST_FAILED${NC}"
  echo ""
  
  if [ $TEST_FAILED -eq 0 ]; then
    echo -e "${GREEN}All tests passed!${NC}"
    exit 0
  else
    echo -e "${RED}Some tests failed.${NC}"
    exit 1
  fi
}

main "$@"
