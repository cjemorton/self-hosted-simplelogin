#!/usr/bin/env bash
#
# startup.sh - Enhanced startup script with MTA-STS detection
#
# This script performs pre-startup checks and MTA-STS detection before
# launching the Docker Compose stack.
#
# Docker Image Validation:
#   This script uses SL_VERSION from .env as the single source of truth for Docker versioning.
#   Before starting:
#     1. Checks if the image exists locally (no remote calls if found)
#     2. If not local, checks the remote Docker registry (Docker Hub)
#     3. If not found anywhere, prints a clear error with instructions
#
#   TODO: Consider automating the build/push process from upstream SimpleLogin images
#         to simplify version management and reduce manual intervention.

set -euo pipefail

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
  echo -e "${BLUE}[INFO]${NC} $*"
}

log_pass() {
  echo -e "${GREEN}[PASS]${NC} $*"
}

log_warn() {
  echo -e "${YELLOW}[WARN]${NC} $*"
}

log_error() {
  echo -e "${RED}[ERROR]${NC} $*"
}

# Print banner
echo ""
echo "========================================="
echo "  SimpleLogin Startup"
echo "========================================="
echo ""

# Check if custom config path is specified, otherwise use .env
CONFIG_FILE="${SL_CONFIG_PATH:-.env}"

# Check if config file exists
if [ ! -f "$CONFIG_FILE" ]; then
  log_error "Configuration file not found: $CONFIG_FILE"
  if [ "$CONFIG_FILE" = ".env" ]; then
    log_info "Please copy .env.example to .env and configure it:"
    log_info "  cp .env.example .env"
  else
    log_info "Please ensure the specified SL_CONFIG_PATH exists:"
    log_info "  SL_CONFIG_PATH=$CONFIG_FILE"
  fi
  exit 1
fi

log_info "Using configuration file: $CONFIG_FILE"

# Load environment variables
# Use a safer method that skips complex syntax
set -a
while IFS= read -r line || [ -n "$line" ]; do
  # Skip comments and empty lines
  if [[ "$line" =~ ^[[:space:]]*# ]] || [[ -z "$line" ]]; then
    continue
  fi
  
  # Only process simple VAR=value lines (no arrays or complex expressions)
  if [[ "$line" =~ ^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
    var_name="${BASH_REMATCH[1]}"
    var_value="${BASH_REMATCH[2]}"
    
    # Skip lines with array syntax or function calls that bash can't handle
    if [[ "$var_value" =~ ^\[.*\]$ ]] || [[ "$var_value" =~ \$\( ]]; then
      continue
    fi
    
    # Export the variable
    export "${var_name}=${var_value}"
  fi
done < "$CONFIG_FILE"
set +a

# Determine which Docker image will be used (single source of truth: .env)
if [ -n "$SL_CUSTOM_IMAGE" ]; then
  # Custom image override is set
  DOCKER_IMAGE="$SL_CUSTOM_IMAGE"
  log_pass "Using custom Docker image: $DOCKER_IMAGE"
  log_info "Note: Custom image overrides SL_DOCKER_REPO, SL_IMAGE, and SL_VERSION"
  log_info "Ensure your custom image is compatible with this SimpleLogin fork"
else
  # Construct image from components (use defaults if not set)
  DOCKER_REPO="${SL_DOCKER_REPO:-clem16}"
  IMAGE_NAME="${SL_IMAGE:-simplelogin-app}"
  
  # Validate SL_VERSION is set
  if [ -z "$SL_VERSION" ]; then
    log_error "SL_VERSION is not set in .env file"
    log_error "Please set SL_VERSION to your desired Docker image tag"
    exit 1
  fi
  
  DOCKER_IMAGE="$DOCKER_REPO/$IMAGE_NAME:$SL_VERSION"
  log_pass "Using Docker image: $DOCKER_IMAGE"
fi

# Check if the Docker image exists locally
log_info "Checking if Docker image exists locally..."
if docker image inspect "$DOCKER_IMAGE" &> /dev/null; then
  log_pass "Docker image found locally: $DOCKER_IMAGE"
else
  log_warn "Docker image not found locally. Checking remote registry..."
  
  # Check if image exists on Docker Hub (or other registry)
  # Use docker manifest inspect which works without pulling the image
  if docker manifest inspect "$DOCKER_IMAGE" &> /dev/null; then
    log_pass "Docker image found on remote registry: $DOCKER_IMAGE"
  else
    log_error ""
    log_error "Docker image not found (locally or remotely): $DOCKER_IMAGE"
    log_error ""
    log_error "Please ensure the image exists by either:"
    log_error "  1. Building and pushing the image to the registry"
    log_error "  2. Setting an existing image tag in your .env file (SL_VERSION=...)"
    log_error ""
    log_error "TODO: Consider automating the build/push process from upstream images"
    log_error "      See: https://github.com/simple-login/app for upstream source"
    exit 1
  fi
fi
echo ""

# Check DNS-01 certificate configuration (Cloudflare)
# This pre-flight check validates Cloudflare credentials for DNS-01 challenges.
# It ONLY runs when LE_CHALLENGE=dns and LE_DNS_PROVIDER=cloudflare are set.
# If valid certificates already exist, it skips the API connectivity test
# to save time and avoid rate limiting.
if [ -f scripts/check-cloudflare-dns.py ] && command -v python3 &> /dev/null; then
  log_info "Running DNS-01 certificate pre-flight check..."
  
  if python3 scripts/check-cloudflare-dns.py --env-file "$CONFIG_FILE"; then
    log_pass "DNS-01 certificate check passed"
  else
    log_error "DNS-01 certificate pre-flight check failed"
    log_error "Cannot proceed with startup - fix the errors above"
    exit 1
  fi
  
  echo ""
fi

# Detect MTA-STS configuration
if [ -f scripts/detect-mta-sts.sh ]; then
  log_info "Detecting MTA-STS configuration..."
  
  # Run detection and capture results
  if scripts/detect-mta-sts.sh; then
    # Export detected configuration
    eval "$(scripts/detect-mta-sts.sh --export 2>/dev/null || echo '')"
  else
    # Detection failed, export defaults
    eval "$(scripts/detect-mta-sts.sh --export 2>/dev/null || echo '')"
  fi
  
  echo ""
fi

# Export MTA-STS configuration for docker-compose
if [ "${MTA_STS_INTERNAL_ENABLED:-true}" = "false" ]; then
  log_info "MTA-STS: External hosting detected or manually disabled"
  log_info "Note: Internal Traefik route will still exist but should not receive traffic"
  log_info "Ensure mta-sts.${DOMAIN} DNS points to your external host (not this server)"
  log_info "Verify external MTA-STS configuration is correct and accessible"
else
  log_info "MTA-STS: Using internal hosting via Traefik"
  log_info "Ensure mta-sts.${DOMAIN} DNS points to this server"
fi

# Export variables for docker-compose to use
export MTA_STS_INTERNAL_ENABLED="${MTA_STS_INTERNAL_ENABLED:-true}"
export MTA_STS_EXTERNAL_DETECTED="${MTA_STS_EXTERNAL_DETECTED:-false}"
export MTA_STS_STATUS="${MTA_STS_STATUS:-internal}"

echo ""
log_info "Pulling latest Docker images..."
docker compose pull

echo ""
log_info "Building postfix image from local Dockerfile..."
docker compose build postfix

echo ""
log_info "Starting Docker Compose stack..."

# Run docker-compose with all arguments passed to this script
docker compose up --remove-orphans --detach "$@"

echo ""
log_pass "SimpleLogin stack started successfully!"
echo ""

# Print MTA-STS status summary
echo "========================================="
echo "  MTA-STS Configuration Summary"
echo "========================================="
echo ""
echo "Mode: ${MTA_STS_MODE:-auto}"
echo "Status: ${MTA_STS_STATUS}"
echo "Internal Hosting: ${MTA_STS_INTERNAL_ENABLED}"
echo "External Detected: ${MTA_STS_EXTERNAL_DETECTED}"
echo ""

if [ "${MTA_STS_EXTERNAL_DETECTED}" = "true" ]; then
  echo "External MTA-STS URL: ${MTA_STS_EXTERNAL_URL:-unknown}"
  echo ""
  log_info "Verify your external MTA-STS configuration at:"
  log_info "  ${MTA_STS_EXTERNAL_URL:-https://mta-sts.${DOMAIN}/.well-known/mta-sts.txt}"
fi

echo ""
log_info "View logs with: docker compose logs -f"
log_info "Stop services with: docker compose down"
echo ""
