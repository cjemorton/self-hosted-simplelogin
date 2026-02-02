#!/usr/bin/env bash
#
# test-mta-sts-detection.sh - Test MTA-STS detection functionality
#
# This script tests the MTA-STS detection and validation logic

set -euo pipefail

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

PASSED=0
FAILED=0

log_test() {
  echo -e "${BLUE}[TEST]${NC} $*"
}

log_pass() {
  echo -e "${GREEN}[PASS]${NC} $*"
  PASSED=$((PASSED + 1))
}

log_fail() {
  echo -e "${RED}[FAIL]${NC} $*"
  FAILED=$((FAILED + 1))
}

# Test 1: Detection script exists and is executable
test_script_exists() {
  log_test "Checking if detect-mta-sts.sh exists and is executable..."
  
  if [ -f scripts/detect-mta-sts.sh ] && [ -x scripts/detect-mta-sts.sh ]; then
    log_pass "detect-mta-sts.sh exists and is executable"
    return 0
  else
    log_fail "detect-mta-sts.sh not found or not executable"
    return 1
  fi
}

# Test 2: Script requires DOMAIN
test_requires_domain() {
  log_test "Testing that script requires DOMAIN..."
  
  local output
  output=$(bash scripts/detect-mta-sts.sh 2>&1 || true)
  
  if echo "$output" | grep -q "DOMAIN not set"; then
    log_pass "Script correctly requires DOMAIN"
    return 0
  else
    log_fail "Script should require DOMAIN"
    echo "Output: $output"
    return 1
  fi
}

# Test 3: Internal mode
test_internal_mode() {
  log_test "Testing internal mode..."
  
  local output
  output=$(DOMAIN=example.com MTA_STS_MODE=internal bash scripts/detect-mta-sts.sh --export 2>/dev/null)
  
  if echo "$output" | grep -q "MTA_STS_INTERNAL_ENABLED=true" && \
     echo "$output" | grep -q "MTA_STS_STATUS=internal"; then
    log_pass "Internal mode works correctly"
    return 0
  else
    log_fail "Internal mode not working as expected"
    echo "Output: $output"
    return 1
  fi
}

# Test 4: External mode
test_external_mode() {
  log_test "Testing external mode..."
  
  local output
  output=$(DOMAIN=example.com MTA_STS_MODE=external bash scripts/detect-mta-sts.sh --export 2>/dev/null)
  
  if echo "$output" | grep -q "MTA_STS_INTERNAL_ENABLED=false" && \
     echo "$output" | grep -q "MTA_STS_STATUS=external"; then
    log_pass "External mode works correctly"
    return 0
  else
    log_fail "External mode not working as expected"
    echo "Output: $output"
    return 1
  fi
}

# Test 5: Disabled mode
test_disabled_mode() {
  log_test "Testing disabled mode..."
  
  local output
  output=$(DOMAIN=example.com MTA_STS_MODE=disabled bash scripts/detect-mta-sts.sh --export 2>/dev/null)
  
  if echo "$output" | grep -q "MTA_STS_INTERNAL_ENABLED=false" && \
     echo "$output" | grep -q "MTA_STS_STATUS=disabled"; then
    log_pass "Disabled mode works correctly"
    return 0
  else
    log_fail "Disabled mode not working as expected"
    echo "Output: $output"
    return 1
  fi
}

# Test 6: Invalid mode
test_invalid_mode() {
  log_test "Testing invalid mode handling..."
  
  local output
  output=$(DOMAIN=example.com MTA_STS_MODE=invalid bash scripts/detect-mta-sts.sh 2>&1 || true)
  
  if echo "$output" | grep -q "Invalid MTA_STS_MODE"; then
    log_pass "Invalid mode correctly rejected"
    return 0
  else
    log_fail "Invalid mode should be rejected"
    echo "Output: $output"
    return 1
  fi
}

# Test 7: Auto mode (no external found)
test_auto_mode_no_external() {
  log_test "Testing auto mode with no external MTA-STS..."
  
  local output
  output=$(DOMAIN=example.com MTA_STS_MODE=auto bash scripts/detect-mta-sts.sh --export 2>/dev/null)
  
  if echo "$output" | grep -q "MTA_STS_INTERNAL_ENABLED=true" && \
     echo "$output" | grep -q "MTA_STS_STATUS=internal"; then
    log_pass "Auto mode defaults to internal when no external found"
    return 0
  else
    log_fail "Auto mode should default to internal"
    echo "Output: $output"
    return 1
  fi
}

# Test 8: Environment variable expansion in compose
test_compose_env_vars() {
  log_test "Testing environment variables in compose file..."
  
  if grep -q "MTA_STS_POLICY_MODE" simple-login-compose.yaml && \
     grep -q "MTA_STS_MAX_AGE" simple-login-compose.yaml; then
    log_pass "Compose file uses MTA-STS environment variables"
    return 0
  else
    log_fail "Compose file should use MTA-STS environment variables"
    return 1
  fi
}

# Test 9: .env.example has MTA-STS variables
test_env_example() {
  log_test "Testing .env.example has MTA-STS variables..."
  
  if grep -q "MTA_STS_MODE" .env.example && \
     grep -q "MTA_STS_POLICY_MODE" .env.example && \
     grep -q "MTA_STS_MAX_AGE" .env.example; then
    log_pass ".env.example includes MTA-STS configuration"
    return 0
  else
    log_fail ".env.example should include MTA-STS configuration"
    return 1
  fi
}

# Test 10: Preflight check includes MTA-STS
test_preflight_check() {
  log_test "Testing preflight check includes MTA-STS validation..."
  
  if grep -q "check_mta_sts" scripts/preflight-check.sh; then
    log_pass "Preflight check includes MTA-STS validation"
    return 0
  else
    log_fail "Preflight check should include MTA-STS validation"
    return 1
  fi
}

# Test 11: README documentation
test_readme_docs() {
  log_test "Testing README includes MTA-STS documentation..."
  
  if grep -q "MTA_STS_MODE" README.md && \
     grep -q "Auto-detection" README.md; then
    log_pass "README includes MTA-STS auto-detection documentation"
    return 0
  else
    log_fail "README should include MTA-STS documentation"
    return 1
  fi
}

# Print banner
echo ""
echo "========================================="
echo "  MTA-STS Detection Test Suite"
echo "========================================="
echo ""

# Run all tests
test_script_exists || true
test_requires_domain || true
test_internal_mode || true
test_external_mode || true
test_disabled_mode || true
test_invalid_mode || true
test_auto_mode_no_external || true
test_compose_env_vars || true
test_env_example || true
test_preflight_check || true
test_readme_docs || true

# Print summary
echo ""
echo "========================================="
echo "  Test Summary"
echo "========================================="
echo ""
printf "${GREEN}Passed:${NC} %d\n" $PASSED
printf "${RED}Failed:${NC} %d\n" $FAILED
echo ""

if [ $FAILED -eq 0 ]; then
  echo -e "${GREEN}✓ All tests passed!${NC}"
  echo ""
  exit 0
else
  echo -e "${RED}✗ Some tests failed!${NC}"
  echo ""
  exit 1
fi
