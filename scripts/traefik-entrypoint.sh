#!/bin/sh
# Traefik Entrypoint Script
# Conditionally configures Traefik based on LE_CHALLENGE environment variable
# This ensures only the appropriate ACME challenge type is enabled

set -e

# Default values
LE_CHALLENGE="${LE_CHALLENGE:-tls}"
LE_EMAIL="${LE_EMAIL:-${SUPPORT_EMAIL:-support@${DOMAIN}}}"

# Test mode flag - if set, print command instead of executing
DRY_RUN="${DRY_RUN:-false}"

# Base Traefik configuration (common to both challenge types)
TRAEFIK_ARGS="
    --accesslog=true
    --ping=true
    --global.sendanonymoususage=false
    --providers.docker.exposedByDefault=false
    --providers.docker.network=traefik
    --entrypoints.web.address=:80
    --entrypoints.web.http.redirections.entrypoint.to=websecure
    --entrypoints.web.http.redirections.entrypoint.scheme=https
    --entrypoints.websecure.address=:443
    --entrypoints.websecure.http.tls.certresolver=${LE_CHALLENGE}
    --experimental.plugins.staticresponse.moduleName=github.com/jdel/staticresponse
    --experimental.plugins.staticresponse.version=v0.0.1
"

# Configure certificate resolver based on LE_CHALLENGE
if [ "$LE_CHALLENGE" = "dns" ]; then
    echo "INFO: Configuring Traefik for DNS-01 ACME challenge"
    echo "INFO: DNS Provider: ${LE_DNS_PROVIDER:-not-set}"
    
    # Validate DNS provider is set
    if [ -z "$LE_DNS_PROVIDER" ]; then
        echo "ERROR: LE_CHALLENGE=dns but LE_DNS_PROVIDER is not set!"
        echo "ERROR: Please set LE_DNS_PROVIDER in your .env file"
        echo "ERROR: See: https://go-acme.github.io/lego/dns/"
        exit 1
    fi
    
    # DNS challenge configuration - only define 'dns' resolver
    TRAEFIK_ARGS="$TRAEFIK_ARGS
        --certificatesresolvers.dns.acme.storage=/etc/traefik/acme/acme-dns.json
        --certificatesresolvers.dns.acme.email=${LE_EMAIL}
        --certificatesresolvers.dns.acme.dnschallenge=true
        --certificatesresolvers.dns.acme.dnschallenge.provider=${LE_DNS_PROVIDER}
    "
    
    echo "INFO: DNS-01 challenge configured successfully"
    echo "INFO: Certificate resolver 'dns' will be used"
    
else
    echo "INFO: Configuring Traefik for TLS-ALPN-01 ACME challenge"
    
    # TLS challenge configuration - only define 'tls' resolver
    TRAEFIK_ARGS="$TRAEFIK_ARGS
        --certificatesresolvers.tls.acme.storage=/etc/traefik/acme/acme-tls.json
        --certificatesresolvers.tls.acme.email=${LE_EMAIL}
        --certificatesresolvers.tls.acme.tlschallenge=true
    "
    
    echo "INFO: TLS-ALPN-01 challenge configured successfully"
    echo "INFO: Certificate resolver 'tls' will be used"
fi

echo "INFO: Starting Traefik..."
echo ""

# Execute Traefik with the constructed arguments
# shellcheck disable=SC2086
if [ "$DRY_RUN" = "true" ]; then
    echo "DRY_RUN: Would execute: /entrypoint.sh traefik $TRAEFIK_ARGS $*"
else
    exec /entrypoint.sh traefik $TRAEFIK_ARGS "$@"
fi
