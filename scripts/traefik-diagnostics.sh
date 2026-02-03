#!/bin/bash
# Traefik ACME Diagnostics Script
# Collects comprehensive diagnostics for troubleshooting certificate issues

set -e

echo "======================================"
echo "Traefik ACME Diagnostics Report"
echo "======================================"
echo "Generated: $(date)"
echo ""

# Check if Traefik container is running
echo "=== Traefik Container Status ==="
if docker ps --format '{{.Names}}' | grep -q "^traefik$"; then
    echo "✅ Traefik container is running"
    docker ps --filter "name=traefik" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
else
    echo "❌ Traefik container is NOT running"
    echo "   Run: docker compose up -d"
    exit 1
fi
echo ""

# Check environment variables
echo "=== Environment Variables ==="
echo "Checking .env configuration..."

# Function to safely get env var from container
get_env_var() {
    local var_name=$1
    local value
    value=$(docker exec traefik env 2>/dev/null | grep "^${var_name}=" | cut -d= -f2- || echo "")
    echo "$value"
}

LE_CHALLENGE=$(get_env_var "LE_CHALLENGE")
LE_DNS_PROVIDER=$(get_env_var "LE_DNS_PROVIDER")
LE_EMAIL=$(get_env_var "LE_EMAIL")
DOMAIN=$(get_env_var "DOMAIN")
SUBDOMAIN=$(get_env_var "SUBDOMAIN")

echo "LE_CHALLENGE: ${LE_CHALLENGE:-not set (will default to 'tls')}"
echo "LE_DNS_PROVIDER: ${LE_DNS_PROVIDER:-not set}"
echo "LE_EMAIL: ${LE_EMAIL:-not set}"
echo "DOMAIN: ${DOMAIN:-not set}"
echo "SUBDOMAIN: ${SUBDOMAIN:-not set}"

# Check DNS provider credentials
if [ "$LE_CHALLENGE" = "dns" ]; then
    echo ""
    echo "DNS Challenge Configuration:"
    
    if [ -z "$LE_DNS_PROVIDER" ]; then
        echo "❌ LE_DNS_PROVIDER is not set!"
        echo "   You must set this in .env file"
    else
        echo "✅ DNS Provider: $LE_DNS_PROVIDER"
        
        # Check provider-specific credentials
        case "$LE_DNS_PROVIDER" in
            cloudflare)
                CF_TOKEN=$(get_env_var "CF_DNS_API_TOKEN")
                CF_API_TOKEN=$(get_env_var "CF_API_TOKEN")
                if [ -n "$CF_TOKEN" ] || [ -n "$CF_API_TOKEN" ]; then
                    echo "✅ Cloudflare API token is set"
                else
                    echo "❌ Cloudflare API token not found!"
                    echo "   Set CF_DNS_API_TOKEN or CF_API_TOKEN in .env"
                fi
                ;;
            azuredns)
                AZURE_CLIENT=$(get_env_var "AZURE_CLIENT_ID")
                if [ -n "$AZURE_CLIENT" ]; then
                    echo "✅ Azure credentials are set"
                else
                    echo "❌ Azure credentials not found!"
                fi
                ;;
            ionos)
                IONOS_KEY=$(get_env_var "IONOS_API_KEY")
                if [ -n "$IONOS_KEY" ]; then
                    echo "✅ IONOS API key is set"
                else
                    echo "❌ IONOS API key not found!"
                fi
                ;;
            *)
                echo "ℹ️  Using DNS provider: $LE_DNS_PROVIDER"
                echo "   Ensure required credentials are set in .env"
                ;;
        esac
    fi
fi
echo ""

# Check Traefik command/arguments
echo "=== Traefik Configuration ==="
echo "Active ACME resolvers:"
docker inspect traefik --format='{{.Args}}' 2>/dev/null | tr ' ' '\n' | grep -E "(certificatesresolver|challenge)" | sed 's/^/  /' || echo "  Could not retrieve configuration"
echo ""

# Check if the right resolver is configured
echo "Certificate resolver analysis:"
if docker inspect traefik --format='{{.Args}}' 2>/dev/null | grep -q "certificatesresolvers.tls.acme.tlschallenge=true"; then
    echo "  ✅ TLS-ALPN resolver is configured"
fi
if docker inspect traefik --format='{{.Args}}' 2>/dev/null | grep -q "certificatesresolvers.dns.acme.dnschallenge=true"; then
    echo "  ✅ DNS resolver is configured"
fi
if docker inspect traefik --format='{{.Args}}' 2>/dev/null | grep -q "certificatesresolvers.tls.acme.tlschallenge=true" && \
   docker inspect traefik --format='{{.Args}}' 2>/dev/null | grep -q "certificatesresolvers.dns.acme.dnschallenge=true"; then
    echo "  ⚠️  WARNING: Both TLS and DNS resolvers are configured!"
    echo "     This may cause issues - only one should be active"
fi
echo ""

# Check router labels
echo "=== Router Configuration ==="
if docker ps --format '{{.Names}}' | grep -q "^sl-app$"; then
    echo "SimpleLogin app router labels:"
    docker inspect sl-app --format='{{range $k, $v := .Config.Labels}}{{if or (eq $k "traefik.http.routers.sl-app.tls.certresolver") (eq $k "traefik.http.routers.dns.tls.certresolver") (eq $k "traefik.http.routers.tls.tls.certresolver")}}{{$k}}={{$v}}{{"\n"}}{{end}}{{end}}' 2>/dev/null | sed 's/^/  /' || echo "  Could not retrieve labels"
else
    echo "⚠️  sl-app container not found"
fi
echo ""

# Check certificate files
echo "=== Certificate Status ==="
echo "Checking ACME storage files..."

# TLS certificates
if docker exec traefik test -f /etc/traefik/acme/acme-tls.json 2>/dev/null; then
    TLS_SIZE=$(docker exec traefik stat -c%s /etc/traefik/acme/acme-tls.json 2>/dev/null)
    TLS_MODIFIED=$(docker exec traefik stat -c%y /etc/traefik/acme/acme-tls.json 2>/dev/null | cut -d. -f1)
    echo "TLS Challenge Certificates (acme-tls.json):"
    echo "  Size: $TLS_SIZE bytes"
    echo "  Modified: $TLS_MODIFIED"
    
    # Try to parse certificates if jq is available
    if docker exec traefik which jq >/dev/null 2>&1; then
        CERT_COUNT=$(docker exec traefik jq -r '.tls.Certificates // [] | length' /etc/traefik/acme/acme-tls.json 2>/dev/null || echo "0")
        echo "  Certificates: $CERT_COUNT"
        if [ "$CERT_COUNT" -gt 0 ]; then
            docker exec traefik jq -r '.tls.Certificates[] | "  - \(.domain.main) (SANs: \(.domain.sans // [] | join(", ")))"' /etc/traefik/acme/acme-tls.json 2>/dev/null || true
        fi
    fi
else
    echo "TLS Challenge Certificates: ❌ File not found"
fi
echo ""

# DNS certificates
if docker exec traefik test -f /etc/traefik/acme/acme-dns.json 2>/dev/null; then
    DNS_SIZE=$(docker exec traefik stat -c%s /etc/traefik/acme/acme-dns.json 2>/dev/null)
    DNS_MODIFIED=$(docker exec traefik stat -c%y /etc/traefik/acme/acme-dns.json 2>/dev/null | cut -d. -f1)
    echo "DNS Challenge Certificates (acme-dns.json):"
    echo "  Size: $DNS_SIZE bytes"
    echo "  Modified: $DNS_MODIFIED"
    
    # Try to parse certificates if jq is available
    if docker exec traefik which jq >/dev/null 2>&1; then
        CERT_COUNT=$(docker exec traefik jq -r '.dns.Certificates // [] | length' /etc/traefik/acme/acme-dns.json 2>/dev/null || echo "0")
        echo "  Certificates: $CERT_COUNT"
        if [ "$CERT_COUNT" -gt 0 ]; then
            docker exec traefik jq -r '.dns.Certificates[] | "  - \(.domain.main) (SANs: \(.domain.sans // [] | join(", ")))"' /etc/traefik/acme/acme-dns.json 2>/dev/null || true
        fi
    fi
else
    echo "DNS Challenge Certificates: ❌ File not found"
fi
echo ""

# Check recent logs
echo "=== Recent Traefik Logs ==="
echo "Last 20 log lines (filtered for ACME-related messages):"
docker logs traefik --tail 100 2>&1 | grep -E "(INFO|ERROR|WARN|challenge|certificate|acme|resolver)" | tail -20 | sed 's/^/  /' || echo "  No relevant logs found"
echo ""

# Network connectivity check
echo "=== Network Connectivity ==="
if [ -n "$DOMAIN" ] && [ -n "$SUBDOMAIN" ]; then
    FULL_DOMAIN="${SUBDOMAIN}.${DOMAIN}"
    echo "Testing connectivity to $FULL_DOMAIN..."
    
    # DNS resolution
    if command -v dig >/dev/null 2>&1; then
        echo "DNS A record:"
        dig +short "$FULL_DOMAIN" A | head -3 | sed 's/^/  /' || echo "  No A records found"
    else
        echo "DNS resolution (dig not available):"
        getent hosts "$FULL_DOMAIN" | sed 's/^/  /' || echo "  Cannot resolve domain"
    fi
    
    # Port check (80 and 443)
    echo ""
    echo "Port accessibility from container:"
    echo "  Note: Testing 'host.docker.internal' (may not work on all Docker setups)"
    docker exec traefik sh -c "command -v nc >/dev/null && nc -zv host.docker.internal 80 2>&1" | sed 's/^/  /' || echo "  nc not available or host.docker.internal not accessible"
    docker exec traefik sh -c "command -v nc >/dev/null && nc -zv host.docker.internal 443 2>&1" | sed 's/^/  /' || echo "  nc not available or host.docker.internal not accessible"
fi
echo ""

# Summary and recommendations
echo "=== Summary & Recommendations ==="
echo ""

# Determine expected vs actual configuration
if [ "$LE_CHALLENGE" = "dns" ]; then
    echo "Expected Configuration: DNS-01 Challenge"
    if docker inspect traefik --format='{{.Args}}' 2>/dev/null | grep -q "certificatesresolvers.dns.acme.dnschallenge=true"; then
        echo "✅ Configuration matches expectation"
    else
        echo "❌ Configuration does NOT match!"
        echo "   Traefik is not configured for DNS challenge"
        echo "   Action: Restart Traefik: docker compose restart traefik"
    fi
    
    if [ -z "$LE_DNS_PROVIDER" ]; then
        echo "❌ Missing LE_DNS_PROVIDER in .env"
        echo "   Action: Add LE_DNS_PROVIDER=cloudflare (or your provider) to .env"
    fi
else
    echo "Expected Configuration: TLS-ALPN Challenge"
    if docker inspect traefik --format='{{.Args}}' 2>/dev/null | grep -q "certificatesresolvers.tls.acme.tlschallenge=true"; then
        echo "✅ Configuration matches expectation"
    else
        echo "❌ Configuration does NOT match!"
        echo "   Traefik is not configured for TLS-ALPN challenge"
        echo "   Action: Restart Traefik: docker compose restart traefik"
    fi
fi

echo ""
echo "======================================"
echo "Diagnostics Complete"
echo "======================================"
echo ""
echo "For detailed troubleshooting, see:"
echo "  TRAEFIK_ACME_TROUBLESHOOTING.md"
echo ""
echo "To view full Traefik logs:"
echo "  docker logs traefik -f"
echo ""
