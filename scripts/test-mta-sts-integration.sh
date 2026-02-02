#!/usr/bin/env bash
#
# test-mta-sts-integration.sh - Integration test for MTA-STS detection
#
# This script simulates various scenarios to test the complete MTA-STS workflow

set -euo pipefail

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

PASSED=0
FAILED=0

log_info() {
  echo -e "${BLUE}[INFO]${NC} $*"
  return 0
}

log_test() {
  echo -e "${BLUE}[TEST]${NC} $*"
  return 0
}

log_pass() {
  echo -e "${GREEN}[PASS]${NC} $*"
  ((PASSED++)) || true
  return 0
}

log_fail() {
  echo -e "${RED}[FAIL]${NC} $*"
  ((FAILED++)) || true
  return 0
}

# Test scenario 1: Auto-detection with no external file
test_auto_no_external() {
  log_test "Scenario 1: Auto-detection with no external file (example.com)"
  
  local stderr_output
  stderr_output=$(DOMAIN=example.com MTA_STS_MODE=auto bash scripts/detect-mta-sts.sh 2>&1 >/dev/null || true)
  
  if echo "$stderr_output" | grep -q "No external MTA-STS file found" && \
     echo "$stderr_output" | grep -q "Using internal MTA-STS hosting"; then
    log_pass "Auto-detection falls back to internal hosting"
  else
    log_fail "Auto-detection should fall back to internal"
    echo "Output: $stderr_output"
  fi
  
  local export_output
  export_output=$(DOMAIN=example.com MTA_STS_MODE=auto bash scripts/detect-mta-sts.sh --export 2>/dev/null || true)
  
  if echo "$export_output" | grep -q "MTA_STS_INTERNAL_ENABLED=true"; then
    log_pass "Internal hosting is enabled"
  else
    log_fail "Internal hosting should be enabled"
    echo "Export output: $export_output"
  fi
  return 0
}

# Test scenario 2: Manual internal mode override
test_manual_internal() {
  log_test "Scenario 2: Manual internal mode override"
  
  local stderr_output
  stderr_output=$(DOMAIN=example.com MTA_STS_MODE=internal bash scripts/detect-mta-sts.sh 2>&1 >/dev/null)
  
  if echo "$stderr_output" | grep -q "Using internal MTA-STS hosting"; then
    log_pass "Internal mode is correctly applied"
  else
    log_fail "Internal mode should be applied"
    echo "Output: $stderr_output"
  fi
  return 0
}

# Test scenario 3: Manual external mode override
test_manual_external() {
  log_test "Scenario 3: Manual external mode override"
  
  local stderr_output
  stderr_output=$(DOMAIN=example.com MTA_STS_MODE=external bash scripts/detect-mta-sts.sh 2>&1 >/dev/null)
  
  if echo "$stderr_output" | grep -q "Using external MTA-STS hosting"; then
    log_pass "External mode is correctly applied"
  else
    log_fail "External mode should be applied"
    echo "Output: $stderr_output"
  fi
  
  local export_output
  export_output=$(DOMAIN=example.com MTA_STS_MODE=external bash scripts/detect-mta-sts.sh --export 2>/dev/null)
  
  if echo "$export_output" | grep -q "MTA_STS_INTERNAL_ENABLED=false"; then
    log_pass "Internal hosting is disabled in external mode"
  else
    log_fail "Internal hosting should be disabled in external mode"
    echo "Export output: $export_output"
  fi
  return 0
}

# Test scenario 4: Disabled mode
test_disabled_mode() {
  log_test "Scenario 4: Disabled mode"
  
  local stderr_output
  stderr_output=$(DOMAIN=example.com MTA_STS_MODE=disabled bash scripts/detect-mta-sts.sh 2>&1 >/dev/null)
  
  if echo "$stderr_output" | grep -q "MTA-STS is disabled"; then
    log_pass "Disabled mode is correctly applied"
  else
    log_fail "Disabled mode should be applied"
    echo "Output: $stderr_output"
  fi
  return 0
}

# Test scenario 5: Environment variable export format
test_export_format() {
  log_test "Scenario 5: Export format validation"
  
  local modes=("internal" "external" "disabled")
  
  for mode in "${modes[@]}"; do
    local export_output
    export_output=$(DOMAIN=example.com MTA_STS_MODE=$mode bash scripts/detect-mta-sts.sh --export 2>/dev/null)
    
    if echo "$export_output" | grep -q "export MTA_STS_INTERNAL_ENABLED=" && \
       echo "$export_output" | grep -q "export MTA_STS_EXTERNAL_DETECTED=" && \
       echo "$export_output" | grep -q "export MTA_STS_STATUS="; then
      log_pass "Export format is valid for mode: $mode"
    else
      log_fail "Export format is invalid for mode: $mode"
      echo "Output: $export_output"
    fi
  done
  return 0
}

# Test scenario 6: Configuration validation in compose file
test_compose_integration() {
  log_test "Scenario 6: Docker Compose integration"
  
  # Check that compose file uses environment variables
  if grep -q '\${MTA_STS_POLICY_MODE:-testing}' simple-login-compose.yaml && \
     grep -q '\${MTA_STS_MAX_AGE:-86400}' simple-login-compose.yaml; then
    log_pass "Compose file correctly uses environment variables"
  else
    log_fail "Compose file should use environment variables"
  fi
  
  # Check that middleware name was updated
  if grep -q 'mta-sts-response' simple-login-compose.yaml; then
    log_pass "Middleware name is correctly set"
  else
    log_fail "Middleware name should be updated"
  fi
  return 0
}

# Test scenario 7: Preflight check integration
test_preflight_integration() {
  log_test "Scenario 7: Preflight check integration"
  
  # Create a temporary .env file for testing
  cat > /tmp/test-mta-sts.env <<EOF
DOMAIN=example.com
SUBDOMAIN=app
POSTGRES_DB=simplelogin
POSTGRES_USER=testuser
POSTGRES_PASSWORD=testpass
FLASK_SECRET=testsecret
SL_VERSION=v4.70.0
SL_IMAGE=app-ci
MTA_STS_MODE=auto
MTA_STS_POLICY_MODE=testing
MTA_STS_MAX_AGE=86400
EOF
  
  local output
  output=$(bash scripts/preflight-check.sh /tmp/test-mta-sts.env 2>&1 || true)
  
  if echo "$output" | grep -q "Checking MTA-STS configuration" && \
     echo "$output" | grep -q "MTA_STS_MODE is set to: auto"; then
    log_pass "Preflight check includes MTA-STS validation"
  else
    log_fail "Preflight check should validate MTA-STS"
    echo "Output: $output"
  fi
  
  rm -f /tmp/test-mta-sts.env
  return 0
}

# Test scenario 8: Documentation completeness
test_documentation() {
  log_test "Scenario 8: Documentation completeness"
  
  local doc_checks=(
    "MTA_STS_MODE"
    "Auto-detection"
    "External Hosting"
    "Cloudflare Pages"
    "MTA_STS_POLICY_MODE"
    "MTA_STS_MAX_AGE"
  )
  
  local all_present=true
  for check in "${doc_checks[@]}"; do
    if ! grep -q "$check" README.md; then
      log_fail "README missing documentation for: $check"
      all_present=false
    fi
  done
  
  if [ "$all_present" = true ]; then
    log_pass "README documentation is complete"
  fi
  return 0
}

# Print banner
echo ""
echo "========================================="
echo "  MTA-STS Integration Test Suite"
echo "========================================="
echo ""

# Run all test scenarios
test_auto_no_external
test_manual_internal
test_manual_external
test_disabled_mode
test_export_format
test_compose_integration
test_preflight_integration
test_documentation

# Print summary
echo ""
echo "========================================="
echo "  Integration Test Summary"
echo "========================================="
echo ""
printf "${GREEN}Passed:${NC} %d\n" $PASSED
printf "${RED}Failed:${NC} %d\n" $FAILED
echo ""

if [ $FAILED -eq 0 ]; then
  echo -e "${GREEN}✓ All integration tests passed!${NC}"
  echo ""
  log_info "MTA-STS auto-detection feature is working correctly"
  echo ""
  exit 0
else
  echo -e "${RED}✗ Some integration tests failed!${NC}"
  echo ""
  exit 1
fi
