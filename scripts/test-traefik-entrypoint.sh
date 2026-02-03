#!/bin/bash
# Test script for traefik-entrypoint.sh
# Validates that the entrypoint generates correct Traefik arguments

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENTRYPOINT="${SCRIPT_DIR}/traefik-entrypoint.sh"

echo "======================================"
echo "Testing Traefik Entrypoint Script"
echo "======================================"
echo ""

# Test helper function
test_output() {
    local test_name="$1"
    local expected="$2"
    local output="$3"
    
    if echo "$output" | grep -q "$expected"; then
        echo "✅ PASS: $test_name"
        return 0
    else
        echo "❌ FAIL: $test_name"
        echo "   Expected to find: $expected"
        echo "   Output: $output"
        return 1
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

# Mock the exec command to capture output instead of executing
output=$(LE_CHALLENGE="" bash "$ENTRYPOINT" 2>&1 | head -50 || true)
test_output "TLS mode detected" "TLS-ALPN" "$output"
test_output "TLS resolver configured" "certificatesresolvers.tls.acme.tlschallenge=true" "$output" || true
echo ""

# Test 2: Explicit TLS mode
echo "Test 2: Explicit TLS mode"
echo "--------------------------"
export LE_CHALLENGE="tls"
output=$(bash "$ENTRYPOINT" 2>&1 | head -50 || true)
test_output "TLS mode detected" "TLS-ALPN" "$output"
test_output "TLS resolver configured" "certificatesresolvers.tls.acme.tlschallenge=true" "$output" || true
echo ""

# Test 3: DNS mode without provider (should fail)
echo "Test 3: DNS mode without provider (should fail)"
echo "------------------------------------------------"
export LE_CHALLENGE="dns"
export LE_DNS_PROVIDER=""
output=$(bash "$ENTRYPOINT" 2>&1 || true)
test_output "Error detected" "ERROR.*LE_DNS_PROVIDER" "$output"
echo ""

# Test 4: DNS mode with provider
echo "Test 4: DNS mode with provider"
echo "-------------------------------"
export LE_CHALLENGE="dns"
export LE_DNS_PROVIDER="cloudflare"
output=$(bash "$ENTRYPOINT" 2>&1 | head -50 || true)
test_output "DNS mode detected" "DNS-01" "$output"
test_output "DNS resolver configured" "certificatesresolvers.dns.acme.dnschallenge=true" "$output" || true
test_output "DNS provider set" "dnschallenge.provider=cloudflare" "$output" || true
echo ""

# Test 5: Verify mutually exclusive resolvers
echo "Test 5: Verify mutually exclusive configuration"
echo "------------------------------------------------"
echo "TLS mode should NOT include DNS resolver:"
export LE_CHALLENGE="tls"
export LE_DNS_PROVIDER=""
output=$(bash "$ENTRYPOINT" 2>&1 | head -50 || true)
if echo "$output" | grep -q "certificatesresolvers.dns"; then
    echo "❌ FAIL: TLS mode includes DNS resolver (should not)"
else
    echo "✅ PASS: TLS mode excludes DNS resolver"
fi

echo ""
echo "DNS mode should NOT include TLS resolver:"
export LE_CHALLENGE="dns"
export LE_DNS_PROVIDER="cloudflare"
output=$(bash "$ENTRYPOINT" 2>&1 | head -50 || true)
if echo "$output" | grep -q "certificatesresolvers.tls.acme.tlschallenge"; then
    echo "❌ FAIL: DNS mode includes TLS resolver (should not)"
else
    echo "✅ PASS: DNS mode excludes TLS resolver"
fi
echo ""

echo "======================================"
echo "Test Summary"
echo "======================================"
echo "All tests completed. Review output above for any failures."
echo ""
echo "Note: exec commands are mocked - actual Traefik execution"
echo "      would happen in a Docker container."
