#!/usr/bin/env bash
#
# startup.sh - Enhanced startup script with MTA-STS detection
#
# This script performs pre-startup checks and MTA-STS detection before
# launching the Docker Compose stack.

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

# Check if .env exists
if [ ! -f .env ]; then
  log_error ".env file not found!"
  log_info "Please copy .env.example to .env and configure it:"
  log_info "  cp .env.example .env"
  exit 1
fi

# Load environment variables
set -a
source .env
set +a

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
  log_warn "Internal MTA-STS via Traefik will still be configured but may conflict with external hosting"
  log_info "Ensure your external MTA-STS configuration is correct"
else
  log_info "MTA-STS: Using internal hosting via Traefik"
fi

# Export variables for docker-compose to use
export MTA_STS_INTERNAL_ENABLED="${MTA_STS_INTERNAL_ENABLED:-true}"
export MTA_STS_EXTERNAL_DETECTED="${MTA_STS_EXTERNAL_DETECTED:-false}"
export MTA_STS_STATUS="${MTA_STS_STATUS:-internal}"

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
