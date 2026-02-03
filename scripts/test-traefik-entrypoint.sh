#!/bin/bash
# Test script for traefik-entrypoint.sh
# Validates that the entrypoint generates correct Traefik arguments
# and ensures mutual exclusivity between DNS and TLS-ALPN challenges

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENTRYPOINT="${SCRIPT_DIR}/traefik-entrypoint.sh"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test counters
TESTS_PASSED=0
TESTS_FAILED=0

echo "======================================"
echo "Testing Traefik Entrypoint Script"
echo "======================================"
echo ""

# Test helper function
test_contains() {
    local test_name="$1"
    local expected="$2"
    local output="$3"
    
    if echo "$output" | grep -qF "$expected"; then
        echo -e "${GREEN}✅ PASS${NC}: $test_name"
        ((TESTS_PASSED++))
        return 0
    else
        echo -e "${RED}❌ FAIL${NC}: $test_name"
        echo "   Expected to find: $expected"
        ((TESTS_FAILED++))
        return 1
    fi
}

# Test helper for ensuring something is NOT present
test_not_contains() {
    local test_name="$1"
    local unexpected="$2"
    local output="$3"
    
    if echo "$output" | grep -qF "$unexpected"; then
        echo -e "${RED}❌ FAIL${NC}: $test_name"
        echo "   Should NOT contain: $unexpected"
        ((TESTS_FAILED++))
        return 1
    else
        echo -e "${GREEN}✅ PASS${NC}: $test_name"
        ((TESTS_PASSED++))
        return 0
    fi
}

# Test 1: Default (TLS-ALPN) mode
echo "Test 1: Default TLS-ALPN mode"
echo "------------------------------"
export LE_CHALLENGE=""
export LE_DNS_PROVIDER=""
export LE_EMAIL="test@example.com"
export DOMAIN="example.com"
export SUPPORT_EMAIL="support@example.com"
export DRY_RUN="true"

output=$(bash "$ENTRYPOINT" 2>&1)
test_contains "TLS mode detected" "TLS-ALPN" "$output" || true
test_contains "TLS resolver configured" "certificatesresolvers.tls.acme.tlschallenge=true" "$output" || true
test_contains "TLS storage configured" "certificatesresolvers.tls.acme.storage=/etc/traefik/acme/acme-tls.json" "$output" || true
test_not_contains "DNS resolver NOT configured" "certificatesresolvers.dns" "$output" || true
echo ""

# Test 2: Explicit TLS mode
echo "Test 2: Explicit TLS mode"
echo "--------------------------"
export LE_CHALLENGE="tls"
export LE_DNS_PROVIDER=""
output=$(bash "$ENTRYPOINT" 2>&1)
test_contains "TLS mode detected" "TLS-ALPN" "$output" || true
test_contains "TLS resolver configured" "certificatesresolvers.tls.acme.tlschallenge=true" "$output" || true
test_not_contains "DNS resolver NOT configured" "certificatesresolvers.dns" "$output" || true
echo ""

# Test 3: DNS mode without provider (should fail)
echo "Test 3: DNS mode without provider (should fail)"
echo "------------------------------------------------"
export LE_CHALLENGE="dns"
export LE_DNS_PROVIDER=""
output=$(bash "$ENTRYPOINT" 2>&1 || true)
if echo "$output" | grep -q "ERROR" && echo "$output" | grep -q "LE_DNS_PROVIDER"; then
    echo -e "${GREEN}✅ PASS${NC}: Error detected"
    ((TESTS_PASSED++))
else
    echo -e "${RED}❌ FAIL${NC}: Error detected"
    ((TESTS_FAILED++))
fi
if echo "$output" | grep -q "not set"; then
    echo -e "${GREEN}✅ PASS${NC}: Error message mentions DNS provider"
    ((TESTS_PASSED++))
else
    echo -e "${RED}❌ FAIL${NC}: Error message mentions DNS provider"
    ((TESTS_FAILED++))
fi
echo ""

# Test 4: DNS mode with provider
echo "Test 4: DNS mode with provider"
echo "-------------------------------"
export LE_CHALLENGE="dns"
export LE_DNS_PROVIDER="cloudflare"
output=$(bash "$ENTRYPOINT" 2>&1)
test_contains "DNS mode detected" "DNS-01" "$output" || true
test_contains "DNS resolver configured" "certificatesresolvers.dns.acme.dnschallenge=true" "$output" || true
test_contains "DNS provider set" "dnschallenge.provider=cloudflare" "$output" || true
test_contains "DNS storage configured" "certificatesresolvers.dns.acme.storage=/etc/traefik/acme/acme-dns.json" "$output" || true
test_not_contains "TLS resolver NOT configured" "certificatesresolvers.tls.acme.tlschallenge" "$output" || true
echo ""

# Test 5: Verify mutually exclusive resolvers - TLS mode
echo "Test 5: Mutual exclusivity - TLS mode"
echo "---------------------------------------"
export LE_CHALLENGE="tls"
export LE_DNS_PROVIDER=""
output=$(bash "$ENTRYPOINT" 2>&1)
test_not_contains "TLS mode excludes DNS resolver" "certificatesresolvers.dns" "$output" || true
test_not_contains "TLS mode excludes DNS challenge" "dnschallenge" "$output" || true
test_contains "TLS mode includes TLS resolver" "certificatesresolvers.tls" "$output" || true
echo ""

# Test 6: Verify mutually exclusive resolvers - DNS mode
echo "Test 6: Mutual exclusivity - DNS mode"
echo "---------------------------------------"
export LE_CHALLENGE="dns"
export LE_DNS_PROVIDER="cloudflare"
output=$(bash "$ENTRYPOINT" 2>&1)
test_not_contains "DNS mode excludes TLS resolver" "certificatesresolvers.tls.acme.tlschallenge" "$output" || true
test_not_contains "DNS mode excludes TLS challenge" "tlschallenge=true" "$output" || true
test_contains "DNS mode includes DNS resolver" "certificatesresolvers.dns" "$output" || true
echo ""

# Test 7: Common configuration present in both modes
echo "Test 7: Common configuration present"
echo "--------------------------------------"
export LE_CHALLENGE="tls"
export LE_DNS_PROVIDER=""
output=$(bash "$ENTRYPOINT" 2>&1)
test_contains "Access log enabled" "accesslog=true" "$output" || true
test_contains "Docker provider configured" "providers.docker" "$output" || true
test_contains "Web entrypoint on port 80" "entrypoints.web.address=:80" "$output" || true
test_contains "Websecure entrypoint on port 443" "entrypoints.websecure.address=:443" "$output" || true
test_contains "HTTP to HTTPS redirect" "redirections.entrypoint.to=websecure" "$output" || true
echo ""

# Test 8: Certificate resolver name matches LE_CHALLENGE
echo "Test 8: Cert resolver name consistency"
echo "----------------------------------------"
export LE_CHALLENGE="tls"
export LE_DNS_PROVIDER=""
output=$(bash "$ENTRYPOINT" 2>&1)
test_contains "TLS certresolver used" "entrypoints.websecure.http.tls.certresolver=tls" "$output" || true

export LE_CHALLENGE="dns"
export LE_DNS_PROVIDER="cloudflare"
output=$(bash "$ENTRYPOINT" 2>&1)
test_contains "DNS certresolver used" "entrypoints.websecure.http.tls.certresolver=dns" "$output" || true
echo ""

# Test 9: Different DNS providers
echo "Test 9: Different DNS providers"
echo "---------------------------------"
for provider in "cloudflare" "route53" "azuredns" "digitalocean"; do
    export LE_CHALLENGE="dns"
    export LE_DNS_PROVIDER="$provider"
    output=$(bash "$ENTRYPOINT" 2>&1)
    test_contains "Provider $provider" "dnschallenge.provider=$provider" "$output" || true
done
echo ""

# Test 10: Email configuration
echo "Test 10: Email configuration"
echo "-----------------------------"
export LE_CHALLENGE="tls"
export LE_EMAIL="custom@example.com"
output=$(bash "$ENTRYPOINT" 2>&1)
test_contains "Custom email used" "acme.email=custom@example.com" "$output" || true

export LE_EMAIL=""
export SUPPORT_EMAIL="fallback@example.com"
output=$(bash "$ENTRYPOINT" 2>&1)
test_contains "Fallback to SUPPORT_EMAIL" "acme.email=fallback@example.com" "$output" || true
echo ""

echo "======================================"
echo "Test Summary"
echo "======================================"
echo -e "Total tests: $((TESTS_PASSED + TESTS_FAILED))"
echo -e "${GREEN}Passed: $TESTS_PASSED${NC}"
echo -e "${RED}Failed: $TESTS_FAILED${NC}"
echo ""

if [ $TESTS_FAILED -eq 0 ]; then
    echo -e "${GREEN}✅ All tests passed!${NC}"
    echo ""
    echo "The traefik-entrypoint.sh script correctly:"
    echo "  ✓ Configures only ONE resolver (DNS or TLS) at a time"
    echo "  ✓ Fails when DNS mode lacks LE_DNS_PROVIDER"
    echo "  ✓ Uses different storage files for each resolver"
    echo "  ✓ Maintains common Traefik configuration"
    echo "  ✓ Properly sets the certresolver name"
    exit 0
else
    echo -e "${RED}❌ Some tests failed!${NC}"
    exit 1
fi
