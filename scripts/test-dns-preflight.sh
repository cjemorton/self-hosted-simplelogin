#!/usr/bin/env bash
#
# test-dns-preflight.sh - Test DNS-01 certificate pre-flight check
#
# This script tests various scenarios for the DNS-01 certificate pre-flight check
# to ensure it behaves correctly under different configurations.
#
# Note: Using 'set -uo pipefail' without '-e' intentionally. The '-e' flag would
# cause the script to exit on the first test failure, preventing us from seeing
# all test results. Each test function explicitly handles errors and reports them.

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

# Create a temporary test environment
setup_test_env() {
  TEST_DIR=$(mktemp -d)
  TEST_ENV="$TEST_DIR/test.env"
  echo "Test directory: $TEST_DIR"
}

cleanup_test_env() {
  rm -rf "$TEST_DIR"
}

# Test 1: DNS-01 not configured (should skip silently)
test_non_dns_challenge() {
  log_test "Test 1: Non-DNS challenge mode (should skip)"
  
  cat > "$TEST_ENV" <<EOF
LE_CHALLENGE=tls
LE_DNS_PROVIDER=cloudflare
DOMAIN=example.com
CF_DNS_API_TOKEN=test-token
EOF
  
  # Capture output first to avoid masking exit code with grep
  output=$(python3 scripts/check-cloudflare-dns.py --env-file "$TEST_ENV" 2>&1 || true)
  
  if echo "$output" | grep -q "not 'dns'"; then
    log_pass "Test 1: Correctly skipped when LE_CHALLENGE != dns"
  else
    log_fail "Test 1: Did not skip as expected"
  fi
}

# Test 2: DNS-01 with non-Cloudflare provider (should skip silently)
test_non_cloudflare_provider() {
  log_test "Test 2: DNS-01 with non-Cloudflare provider (should skip)"
  
  cat > "$TEST_ENV" <<EOF
LE_CHALLENGE=dns
LE_DNS_PROVIDER=route53
DOMAIN=example.com
EOF
  
  # Capture output first to avoid masking exit code with grep
  output=$(python3 scripts/check-cloudflare-dns.py --env-file "$TEST_ENV" 2>&1 || true)
  
  if echo "$output" | grep -q "not 'cloudflare'"; then
    log_pass "Test 2: Correctly skipped when provider != cloudflare"
  else
    log_fail "Test 2: Did not skip as expected"
  fi
}

# Test 3: DNS-01 with Cloudflare but missing credentials (should fail)
test_missing_credentials() {
  log_test "Test 3: DNS-01 with Cloudflare but missing credentials (should fail)"
  
  cat > "$TEST_ENV" <<EOF
LE_CHALLENGE=dns
LE_DNS_PROVIDER=cloudflare
DOMAIN=example.com
SUBDOMAIN=app
EOF
  
  # Capture output first, then grep (don't use pipe with non-zero exit)
  output=$(python3 scripts/check-cloudflare-dns.py --env-file "$TEST_ENV" 2>&1 || true)
  
  if echo "$output" | grep -q "Cloudflare API token is required"; then
    log_pass "Test 3: Correctly detected missing credentials"
  else
    log_fail "Test 3: Did not detect missing credentials"
  fi
}

# Test 4: DNS-01 with Cloudflare and credentials present (basic check)
test_credentials_present() {
  log_test "Test 4: Credentials present check"
  
  cat > "$TEST_ENV" <<EOF
LE_CHALLENGE=dns
LE_DNS_PROVIDER=cloudflare
DOMAIN=example.com
CF_DNS_API_TOKEN=test-token-12345
EOF
  
  # This will fail on API connectivity, but should pass credential presence check
  output=$(python3 scripts/check-cloudflare-dns.py --env-file "$TEST_ENV" 2>&1 || true)
  
  if echo "$output" | grep -q "Cloudflare API token found"; then
    log_pass "Test 4: Correctly found credentials"
  else
    log_fail "Test 4: Did not find credentials"
  fi
}

# Test 5: Invalid domain configuration
test_invalid_domain() {
  log_test "Test 5: Invalid domain configuration (should fail)"
  
  cat > "$TEST_ENV" <<EOF
LE_CHALLENGE=dns
LE_DNS_PROVIDER=cloudflare
DOMAIN=paste-domain-here
CF_DNS_API_TOKEN=test-token
EOF
  
  # Capture output first, then grep (don't use pipe with non-zero exit)
  output=$(python3 scripts/check-cloudflare-dns.py --env-file "$TEST_ENV" 2>&1 || true)
  
  if echo "$output" | grep -q "DOMAIN is not configured properly"; then
    log_pass "Test 5: Correctly detected invalid domain"
  else
    log_fail "Test 5: Did not detect invalid domain"
  fi
}

# Print summary
print_summary() {
  echo ""
  echo "========================================="
  echo "  Test Summary"
  echo "========================================="
  echo ""
  echo -e "${GREEN}Passed: ${TEST_PASSED}${NC}"
  echo -e "${RED}Failed: ${TEST_FAILED}${NC}"
  echo ""
  
  if [ $TEST_FAILED -eq 0 ]; then
    echo -e "${GREEN}✓ All tests passed!${NC}"
    return 0
  else
    echo -e "${RED}✗ Some tests failed${NC}"
    return 1
  fi
}

# Main execution
main() {
  echo ""
  echo "========================================="
  echo "  DNS-01 Pre-flight Check Tests"
  echo "========================================="
  echo ""
  
  setup_test_env
  
  test_non_dns_challenge
  test_non_cloudflare_provider
  test_missing_credentials
  test_credentials_present
  test_invalid_domain
  
  cleanup_test_env
  
  if print_summary; then
    exit 0
  else
    exit 1
  fi
}

main "$@"
