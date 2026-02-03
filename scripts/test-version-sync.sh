#!/usr/bin/env bash
#
# test-version-sync.sh - Test version synchronization features in up.sh
#
# This script tests the new --update-latest flag and related features

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

# Test 1: Verify --update-latest flag exists in help
test_update_latest_flag_in_help() {
  log_test "Checking if --update-latest flag is documented..."
  
  if output=$(./up.sh -h 2>&1); then
    if echo "$output" | grep -q "update-latest"; then
      log_pass "Help output documents the --update-latest flag"
    else
      log_fail "Help output does not document the --update-latest flag"
      return 1
    fi
  else
    log_fail "Failed to run up.sh -h"
    return 1
  fi
}

# Test 2: Verify --no-docker-login-check flag exists in help
test_no_docker_login_check_in_help() {
  log_test "Checking if --no-docker-login-check flag is documented..."
  
  if output=$(./up.sh -h 2>&1); then
    if echo "$output" | grep -q "no-docker-login-check"; then
      log_pass "Help output documents the --no-docker-login-check flag"
    else
      log_fail "Help output does not document the --no-docker-login-check flag"
      return 1
    fi
  else
    log_fail "Failed to run up.sh -h"
    return 1
  fi
}

# Test 3: Verify --retry-delay flag exists in help
test_retry_delay_in_help() {
  log_test "Checking if --retry-delay flag is documented..."
  
  if output=$(./up.sh -h 2>&1); then
    if echo "$output" | grep -q "retry-delay"; then
      log_pass "Help output documents the --retry-delay flag"
    else
      log_fail "Help output does not document the --retry-delay flag"
      return 1
    fi
  else
    log_fail "Failed to run up.sh -h"
    return 1
  fi
}

# Test 4: Verify --max-retries flag exists in help
test_max_retries_in_help() {
  log_test "Checking if --max-retries flag is documented..."
  
  if output=$(./up.sh -h 2>&1); then
    if echo "$output" | grep -q "max-retries"; then
      log_pass "Help output documents the --max-retries flag"
    else
      log_fail "Help output does not document the --max-retries flag"
      return 1
    fi
  else
    log_fail "Failed to run up.sh -h"
    return 1
  fi
}

# Test 5: Verify Version Synchronization section exists in help
test_version_sync_section_in_help() {
  log_test "Checking if help has Version Synchronization section..."
  
  if output=$(./up.sh -h 2>&1); then
    if echo "$output" | grep -q "Version Synchronization"; then
      log_pass "Help output includes Version Synchronization section"
    else
      log_fail "Help output does not include Version Synchronization section"
      return 1
    fi
  else
    log_fail "Failed to run up.sh -h"
    return 1
  fi
}

# Test 6: Verify environment variables are documented
test_env_vars_documented() {
  log_test "Checking if environment variables are documented..."
  
  if output=$(./up.sh -h 2>&1); then
    if echo "$output" | grep -q "Environment Variables"; then
      log_pass "Help output documents environment variables"
    else
      log_fail "Help output does not document environment variables"
      return 1
    fi
    
    if echo "$output" | grep -q "SL_DOCKER_REPO"; then
      log_pass "Help output mentions SL_DOCKER_REPO"
    else
      log_fail "Help output does not mention SL_DOCKER_REPO"
      return 1
    fi
  else
    log_fail "Failed to run up.sh -h"
    return 1
  fi
}

# Test 7: Verify retry behavior is documented
test_retry_behavior_documented() {
  log_test "Checking if retry behavior is documented..."
  
  if output=$(./up.sh -h 2>&1); then
    if echo "$output" | grep -q "Retry Behavior"; then
      log_pass "Help output documents retry behavior"
    else
      log_fail "Help output does not document retry behavior"
      return 1
    fi
  else
    log_fail "Failed to run up.sh -h"
    return 1
  fi
}

# Test 8: Verify Docker Login Check is documented
test_docker_login_check_documented() {
  log_test "Checking if Docker login check is documented..."
  
  if output=$(./up.sh -h 2>&1); then
    if echo "$output" | grep -q "Docker Login Check"; then
      log_pass "Help output documents Docker login check"
    else
      log_fail "Help output does not document Docker login check"
      return 1
    fi
  else
    log_fail "Failed to run up.sh -h"
    return 1
  fi
}

# Test 9: Verify fallback behavior is documented
test_fallback_behavior_documented() {
  log_test "Checking if fallback behavior is documented..."
  
  if output=$(./up.sh -h 2>&1); then
    if echo "$output" | grep -q "Falls back"; then
      log_pass "Help output documents fallback behavior"
    else
      log_fail "Help output does not document fallback behavior"
      return 1
    fi
  else
    log_fail "Failed to run up.sh -h"
    return 1
  fi
}

# Test 10: Verify UPDATE_LATEST variable exists in script
test_update_latest_variable() {
  log_test "Checking if UPDATE_LATEST variable exists..."
  
  if grep -q "UPDATE_LATEST=false" up.sh; then
    log_pass "UPDATE_LATEST variable found in up.sh"
  else
    log_fail "UPDATE_LATEST variable not found in up.sh"
    return 1
  fi
}

# Test 11: Verify NO_DOCKER_LOGIN_CHECK variable exists in script
test_no_docker_login_check_variable() {
  log_test "Checking if NO_DOCKER_LOGIN_CHECK variable exists..."
  
  if grep -q "NO_DOCKER_LOGIN_CHECK=false" up.sh; then
    log_pass "NO_DOCKER_LOGIN_CHECK variable found in up.sh"
  else
    log_fail "NO_DOCKER_LOGIN_CHECK variable not found in up.sh"
    return 1
  fi
}

# Test 12: Verify RETRY_DELAY variable exists in script
test_retry_delay_variable() {
  log_test "Checking if RETRY_DELAY variable exists..."
  
  if grep -q "RETRY_DELAY=" up.sh; then
    log_pass "RETRY_DELAY variable found in up.sh"
  else
    log_fail "RETRY_DELAY variable not found in up.sh"
    return 1
  fi
  
  # Check default value
  if grep -q "RETRY_DELAY=15" up.sh; then
    log_pass "RETRY_DELAY defaults to 15 seconds"
  else
    log_fail "RETRY_DELAY does not default to 15 seconds"
    return 1
  fi
}

# Test 13: Verify MAX_RETRIES variable exists in script
test_max_retries_variable() {
  log_test "Checking if MAX_RETRIES variable exists..."
  
  if grep -q "MAX_RETRIES=" up.sh; then
    log_pass "MAX_RETRIES variable found in up.sh"
  else
    log_fail "MAX_RETRIES variable not found in up.sh"
    return 1
  fi
  
  # Check default value
  if grep -q "MAX_RETRIES=20" up.sh; then
    log_pass "MAX_RETRIES defaults to 20"
  else
    log_fail "MAX_RETRIES does not default to 20"
    return 1
  fi
}

# Test 14: Verify logging helper functions exist
test_logging_functions() {
  log_test "Checking if logging helper functions exist..."
  
  if grep -q "log_info()" up.sh; then
    log_pass "log_info function found in up.sh"
  else
    log_fail "log_info function not found in up.sh"
    return 1
  fi
  
  if grep -q "log_success()" up.sh; then
    log_pass "log_success function found in up.sh"
  else
    log_fail "log_success function not found in up.sh"
    return 1
  fi
  
  if grep -q "log_error()" up.sh; then
    log_pass "log_error function found in up.sh"
  else
    log_fail "log_error function not found in up.sh"
    return 1
  fi
  
  if grep -q "log_warning()" up.sh; then
    log_pass "log_warning function found in up.sh"
  else
    log_fail "log_warning function not found in up.sh"
    return 1
  fi
}

# Test 15: Verify check_docker_login function exists
test_check_docker_login_function() {
  log_test "Checking if check_docker_login function exists..."
  
  if grep -q "check_docker_login()" up.sh; then
    log_pass "check_docker_login function found in up.sh"
  else
    log_fail "check_docker_login function not found in up.sh"
    return 1
  fi
  
  # Check if it uses docker info
  if grep -q 'docker info.*Username' up.sh; then
    log_pass "check_docker_login uses docker info to check Username"
  else
    log_fail "check_docker_login does not check Username"
    return 1
  fi
}

# Test 16: Verify fetch_latest_github_tag function exists
test_fetch_latest_github_tag_function() {
  log_test "Checking if fetch_latest_github_tag function exists..."
  
  if grep -q "fetch_latest_github_tag()" up.sh; then
    log_pass "fetch_latest_github_tag function found in up.sh"
  else
    log_fail "fetch_latest_github_tag function not found in up.sh"
    return 1
  fi
  
  # Check if it uses GitHub API
  if grep -q "api.github.com" up.sh; then
    log_pass "fetch_latest_github_tag uses GitHub API"
  else
    log_fail "fetch_latest_github_tag does not use GitHub API"
    return 1
  fi
}

# Test 17: Verify check_docker_image_exists function exists
test_check_docker_image_exists_function() {
  log_test "Checking if check_docker_image_exists function exists..."
  
  if grep -q "check_docker_image_exists()" up.sh; then
    log_pass "check_docker_image_exists function found in up.sh"
  else
    log_fail "check_docker_image_exists function not found in up.sh"
    return 1
  fi
  
  # Check if it uses docker manifest inspect
  if grep -q "docker manifest inspect" up.sh; then
    log_pass "check_docker_image_exists uses docker manifest inspect"
  else
    log_fail "check_docker_image_exists does not use docker manifest inspect"
    return 1
  fi
}

# Test 18: Verify update_env_version function exists
test_update_env_version_function() {
  log_test "Checking if update_env_version function exists..."
  
  if grep -q "update_env_version()" up.sh; then
    log_pass "update_env_version function found in up.sh"
  else
    log_fail "update_env_version function not found in up.sh"
    return 1
  fi
  
  # Check if it creates backup
  if grep -q ".env.backup" up.sh; then
    log_pass "update_env_version creates backup"
  else
    log_fail "update_env_version does not create backup"
    return 1
  fi
  
  # Check if it updates SL_VERSION using sed
  if grep "update_env_version" up.sh -A20 | grep -q "sed.*SL_VERSION"; then
    log_pass "update_env_version updates SL_VERSION using sed"
  else
    log_fail "update_env_version does not properly update SL_VERSION"
    return 1
  fi
}

# Test 19: Verify perform_version_update function exists
test_perform_version_update_function() {
  log_test "Checking if perform_version_update function exists..."
  
  if grep -q "perform_version_update()" up.sh; then
    log_pass "perform_version_update function found in up.sh"
  else
    log_fail "perform_version_update function not found in up.sh"
    return 1
  fi
  
  # Check if it implements retry logic
  if grep -q "retry_count" up.sh; then
    log_pass "perform_version_update implements retry logic"
  else
    log_fail "perform_version_update does not implement retry logic"
    return 1
  fi
  
  # Check if it implements fallback
  if grep -q "fallback" up.sh; then
    log_pass "perform_version_update implements fallback logic"
  else
    log_fail "perform_version_update does not implement fallback logic"
    return 1
  fi
}

# Test 20: Verify error handling for network issues
test_error_handling() {
  log_test "Checking if error handling is implemented..."
  
  # Check for error messages
  if grep -q "Network issue\|API unavailable\|Failed to fetch" up.sh; then
    log_pass "Error handling for network issues found"
  else
    log_fail "Error handling for network issues not found"
    return 1
  fi
  
  # Check for permission error handling
  if grep -q "permission" up.sh; then
    log_pass "Error handling mentions permissions"
  else
    log_info "Note: Specific permission error handling not explicitly mentioned"
  fi
}

# Test 21: Verify retry-delay parameter validation
test_retry_delay_validation() {
  log_test "Checking retry-delay parameter validation..."
  
  # The script should validate that retry-delay is a number
  if grep -A5 "retry-delay)" up.sh | grep -q "0-9"; then
    log_pass "retry-delay parameter validation found"
  else
    log_fail "retry-delay parameter validation not found"
    return 1
  fi
}

# Test 22: Verify max-retries parameter validation
test_max_retries_validation() {
  log_test "Checking max-retries parameter validation..."
  
  # The script should validate that max-retries is a number
  if grep -A5 "max-retries)" up.sh | grep -q "0-9"; then
    log_pass "max-retries parameter validation found"
  else
    log_fail "max-retries parameter validation not found"
    return 1
  fi
}

# Test 23: Verify option parsing for new flags
test_option_parsing() {
  log_test "Checking option parsing for new flags..."
  
  if grep -q "update-latest)" up.sh; then
    log_pass "Option parsing for --update-latest found"
  else
    log_fail "Option parsing for --update-latest not found"
    return 1
  fi
  
  if grep -q "no-docker-login-check)" up.sh; then
    log_pass "Option parsing for --no-docker-login-check found"
  else
    log_fail "Option parsing for --no-docker-login-check not found"
    return 1
  fi
  
  if grep -q "retry-delay)" up.sh; then
    log_pass "Option parsing for --retry-delay found"
  else
    log_fail "Option parsing for --retry-delay not found"
    return 1
  fi
  
  if grep -q "max-retries)" up.sh; then
    log_pass "Option parsing for --max-retries found"
  else
    log_fail "Option parsing for --max-retries not found"
    return 1
  fi
}

# Test 24: Verify execution order (Docker login check before operations)
test_execution_order() {
  log_test "Checking if Docker login check is executed before operations..."
  
  # Find line numbers
  local docker_check_line=$(grep -n "check_docker_login" up.sh | head -1 | cut -d':' -f1)
  local cleanup_line=$(grep -n "perform_cleanup" up.sh | head -1 | cut -d':' -f1)
  
  if [ -n "$docker_check_line" ] && [ -n "$cleanup_line" ]; then
    if [ "$docker_check_line" -lt "$cleanup_line" ]; then
      log_pass "Docker login check is executed before cleanup"
    else
      log_fail "Docker login check is not executed before cleanup"
      return 1
    fi
  else
    log_fail "Could not find execution order"
    return 1
  fi
}

# Test 25: Verify Docker login check can be skipped
test_docker_login_check_skip() {
  log_test "Checking if Docker login check can be skipped..."
  
  if grep -q 'if.*NO_DOCKER_LOGIN_CHECK.*!= true' up.sh; then
    log_pass "Docker login check can be skipped with --no-docker-login-check"
  else
    log_fail "Docker login check cannot be properly skipped"
    return 1
  fi
}

# Test 26: Verify validate_tag function exists
test_validate_tag_function() {
  log_test "Checking if validate_tag function exists..."
  
  if grep -q "validate_tag()" scripts/up.sh; then
    log_pass "validate_tag function found in up.sh"
  else
    log_fail "validate_tag function not found in up.sh"
    return 1
  fi
  
  # Check if it validates for spaces
  if grep "validate_tag" scripts/up.sh -A20 | grep -q "spaces"; then
    log_pass "validate_tag checks for spaces"
  else
    log_fail "validate_tag does not check for spaces"
    return 1
  fi
  
  # Check if it validates for newlines
  if grep "validate_tag" scripts/up.sh -A20 | grep -q "newlines"; then
    log_pass "validate_tag checks for newlines"
  else
    log_fail "validate_tag does not check for newlines"
    return 1
  fi
}

# Test 27: Verify sanitize_tag function exists
test_sanitize_tag_function() {
  log_test "Checking if sanitize_tag function exists..."
  
  if grep -q "sanitize_tag()" scripts/up.sh; then
    log_pass "sanitize_tag function found in up.sh"
  else
    log_fail "sanitize_tag function not found in up.sh"
    return 1
  fi
}

# Test 28: Test tag validation logic
test_tag_validation_multiline() {
  log_test "Testing tag validation with simulated multi-line output..."
  
  # Create a temporary test script that sources the functions
  local test_script=$(mktemp)
  cat > "$test_script" << 'EOFTEST'
#!/bin/bash
# Extract and test validation functions
source <(sed -n '/^validate_tag()/,/^}/p' scripts/up.sh)
source <(sed -n '/^sanitize_tag()/,/^}/p' scripts/up.sh)

# Override log functions to avoid dependency issues
log_error() { echo "ERROR: $*" >&2; }

# Test case 1: Clean tag should pass validation
clean_tag="v2026.02.02-staging-test-04"
if validate_tag "$clean_tag" 2>/dev/null; then
  echo "PASS: Clean tag validation"
else
  echo "FAIL: Clean tag validation"
  exit 1
fi

# Test case 2: Tag with spaces should fail validation
polluted_tag="[INFO] Fetching latest tag v2026.02.02-staging-test-04"
if ! validate_tag "$polluted_tag" 2>/dev/null; then
  echo "PASS: Polluted tag validation correctly failed"
else
  echo "FAIL: Polluted tag should have failed validation"
  exit 1
fi

# Test case 3: Sanitize should extract only the tag
sanitized=$(sanitize_tag "$polluted_tag")
if [ "$sanitized" = "$clean_tag" ]; then
  echo "PASS: Tag sanitization extracted clean tag"
else
  echo "FAIL: Tag sanitization failed. Expected: $clean_tag, Got: $sanitized"
  exit 1
fi

# Test case 4: Sanitized tag should pass validation
if validate_tag "$sanitized" 2>/dev/null; then
  echo "PASS: Sanitized tag validation"
else
  echo "FAIL: Sanitized tag validation failed"
  exit 1
fi
EOFTEST

  # Run the test script
  if bash "$test_script" 2>&1 | grep -q "^FAIL"; then
    log_fail "Tag validation tests failed"
    rm -f "$test_script"
    return 1
  else
    log_pass "Tag validation and sanitization tests passed"
    rm -f "$test_script"
  fi
}

# Test 29: Verify logging functions output to stderr
test_logging_to_stderr() {
  log_test "Checking if logging functions output to stderr..."
  
  # Check if log functions redirect to stderr (>&2)
  if grep -A2 "^log_info()" scripts/up.sh | grep -q ">&2"; then
    log_pass "log_info outputs to stderr"
  else
    log_fail "log_info does not output to stderr"
    return 1
  fi
  
  if grep -A2 "^log_success()" scripts/up.sh | grep -q ">&2"; then
    log_pass "log_success outputs to stderr"
  else
    log_fail "log_success does not output to stderr"
    return 1
  fi
  
  if grep -A2 "^log_warning()" scripts/up.sh | grep -q ">&2"; then
    log_pass "log_warning outputs to stderr"
  else
    log_fail "log_warning does not output to stderr"
    return 1
  fi
}

# Test 30: Verify tag sanitization is used in perform_version_update
test_tag_sanitization_in_perform_version_update() {
  log_test "Checking if tag sanitization is used in perform_version_update..."
  
  if grep "perform_version_update" scripts/up.sh -A100 | grep -q "sanitize_tag"; then
    log_pass "perform_version_update uses sanitize_tag"
  else
    log_fail "perform_version_update does not use sanitize_tag"
    return 1
  fi
  
  if grep "perform_version_update" scripts/up.sh -A100 | grep -q "validate_tag"; then
    log_pass "perform_version_update uses validate_tag"
  else
    log_fail "perform_version_update does not use validate_tag"
    return 1
  fi
}

# Main test execution
main() {
  echo "=========================================="
  echo "Testing Version Synchronization Features"
  echo "=========================================="
  echo ""
  
  # Change to repository root
  cd "$(dirname "$0")/.." || exit 1
  
  log_info "Working directory: $(pwd)"
  log_info "Testing up.sh script..."
  echo ""
  
  # Run all tests
  test_update_latest_flag_in_help
  echo ""
  test_no_docker_login_check_in_help
  echo ""
  test_retry_delay_in_help
  echo ""
  test_max_retries_in_help
  echo ""
  test_version_sync_section_in_help
  echo ""
  test_env_vars_documented
  echo ""
  test_retry_behavior_documented
  echo ""
  test_docker_login_check_documented
  echo ""
  test_fallback_behavior_documented
  echo ""
  test_update_latest_variable
  echo ""
  test_no_docker_login_check_variable
  echo ""
  test_retry_delay_variable
  echo ""
  test_max_retries_variable
  echo ""
  test_logging_functions
  echo ""
  test_check_docker_login_function
  echo ""
  test_fetch_latest_github_tag_function
  echo ""
  test_check_docker_image_exists_function
  echo ""
  test_update_env_version_function
  echo ""
  test_perform_version_update_function
  echo ""
  test_error_handling
  echo ""
  test_retry_delay_validation
  echo ""
  test_max_retries_validation
  echo ""
  test_option_parsing
  echo ""
  test_execution_order
  echo ""
  test_docker_login_check_skip
  echo ""
  test_validate_tag_function
  echo ""
  test_sanitize_tag_function
  echo ""
  test_tag_validation_multiline
  echo ""
  test_logging_to_stderr
  echo ""
  test_tag_sanitization_in_perform_version_update
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
