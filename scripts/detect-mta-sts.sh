#!/usr/bin/env bash
#
# detect-mta-sts.sh - Auto-detect external MTA-STS hosting
#
# This script checks if MTA-STS is hosted externally at:
#   https://mta-sts.<domain>/.well-known/mta-sts.txt
#
# It validates the external file and determines if internal hosting should be disabled.
#
# Usage: 
#   ./detect-mta-sts.sh [domain]
#   ./detect-mta-sts.sh --export  # Output environment variables
#
# Environment Variables:
#   DOMAIN - The domain to check (required if not passed as argument)
#   MTA_STS_MODE - Override mode: auto, internal, external, disabled
#   MTA_STS_POLICY_MODE - Policy mode: testing, enforce, none
#   MTA_STS_MAX_AGE - Max age in seconds (default: 86400)
#
# Exit codes:
#   0 - Detection successful
#   1 - External MTA-STS not found or invalid
#   2 - Configuration error
#
# Output modes:
#   - Normal: Human-readable status and recommendations
#   - Export: Shell environment variables for sourcing

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Parse arguments
EXPORT_MODE=false
DOMAIN_ARG=""

for arg in "$@"; do
  case $arg in
    --export)
      EXPORT_MODE=true
      ;;
    *)
      DOMAIN_ARG="$arg"
      ;;
  esac
done

# Logging functions
log_info() {
  if [ "$EXPORT_MODE" = false ]; then
    echo -e "${BLUE}[MTA-STS]${NC} $*" >&2
  fi
}

log_pass() {
  if [ "$EXPORT_MODE" = false ]; then
    echo -e "${GREEN}[MTA-STS]${NC} $*" >&2
  fi
}

log_fail() {
  if [ "$EXPORT_MODE" = false ]; then
    echo -e "${RED}[MTA-STS]${NC} $*" >&2
  fi
}

log_warn() {
  if [ "$EXPORT_MODE" = false ]; then
    echo -e "${YELLOW}[MTA-STS]${NC} $*" >&2
  fi
}

# Get domain from argument or environment
DOMAIN="${DOMAIN_ARG:-${DOMAIN:-}}"

if [ -z "$DOMAIN" ]; then
  log_fail "DOMAIN not set. Please set DOMAIN environment variable or pass as argument."
  exit 2
fi

# Get MTA-STS configuration
MTA_STS_MODE="${MTA_STS_MODE:-auto}"
MTA_STS_POLICY_MODE="${MTA_STS_POLICY_MODE:-testing}"
MTA_STS_MAX_AGE="${MTA_STS_MAX_AGE:-86400}"
SUBDOMAIN="${SUBDOMAIN:-app}"

# Validate MTA_STS_MODE
case "$MTA_STS_MODE" in
  auto|internal|external|disabled)
    ;;
  *)
    log_fail "Invalid MTA_STS_MODE: $MTA_STS_MODE (must be: auto, internal, external, or disabled)"
    exit 2
    ;;
esac

# If mode is not auto, skip detection
if [ "$MTA_STS_MODE" != "auto" ]; then
  log_info "MTA-STS mode set to '$MTA_STS_MODE' (manual override, skipping auto-detection)"
  
  case "$MTA_STS_MODE" in
    internal)
      log_info "Using internal MTA-STS hosting via Traefik"
      if [ "$EXPORT_MODE" = true ]; then
        echo "export MTA_STS_INTERNAL_ENABLED=true"
        echo "export MTA_STS_EXTERNAL_DETECTED=false"
        echo "export MTA_STS_STATUS=internal"
      fi
      exit 0
      ;;
    external)
      log_info "Using external MTA-STS hosting (internal hosting disabled)"
      if [ "$EXPORT_MODE" = true ]; then
        echo "export MTA_STS_INTERNAL_ENABLED=false"
        echo "export MTA_STS_EXTERNAL_DETECTED=true"
        echo "export MTA_STS_STATUS=external"
      fi
      exit 0
      ;;
    disabled)
      log_warn "MTA-STS is disabled (not recommended for production)"
      if [ "$EXPORT_MODE" = true ]; then
        echo "export MTA_STS_INTERNAL_ENABLED=false"
        echo "export MTA_STS_EXTERNAL_DETECTED=false"
        echo "export MTA_STS_STATUS=disabled"
      fi
      exit 0
      ;;
  esac
fi

# Auto-detection mode
log_info "Auto-detecting MTA-STS configuration for domain: $DOMAIN"

# Check if curl is available
if ! command -v curl &> /dev/null; then
  log_warn "curl not found, cannot detect external MTA-STS hosting"
  log_info "Defaulting to internal hosting"
  if [ "$EXPORT_MODE" = true ]; then
    echo "export MTA_STS_INTERNAL_ENABLED=true"
    echo "export MTA_STS_EXTERNAL_DETECTED=false"
    echo "export MTA_STS_STATUS=internal"
  fi
  exit 0
fi

# Construct MTA-STS URL
MTA_STS_URL="https://mta-sts.${DOMAIN}/.well-known/mta-sts.txt"

log_info "Checking for external MTA-STS at: $MTA_STS_URL"

# Attempt to fetch external MTA-STS file with timeout
# Use --max-time to prevent hanging
EXTERNAL_CONTENT=$(curl -sSL --max-time 10 --fail "$MTA_STS_URL" 2>/dev/null || echo "")

if [ -z "$EXTERNAL_CONTENT" ]; then
  log_info "No external MTA-STS file found or not accessible"
  log_info "Using internal MTA-STS hosting via Traefik"
  
  if [ "$EXPORT_MODE" = true ]; then
    echo "export MTA_STS_INTERNAL_ENABLED=true"
    echo "export MTA_STS_EXTERNAL_DETECTED=false"
    echo "export MTA_STS_STATUS=internal"
  fi
  exit 1
fi

# Validate external MTA-STS content
log_info "External MTA-STS file found, validating content..."

# Check for required fields
VALID=true

if ! echo "$EXTERNAL_CONTENT" | grep -q "version:.*STSv1"; then
  log_fail "External MTA-STS missing 'version: STSv1' field"
  VALID=false
fi

if ! echo "$EXTERNAL_CONTENT" | grep -q "mode:"; then
  log_fail "External MTA-STS missing 'mode' field"
  VALID=false
fi

if ! echo "$EXTERNAL_CONTENT" | grep -q "mx:"; then
  log_fail "External MTA-STS missing 'mx' field"
  VALID=false
fi

if ! echo "$EXTERNAL_CONTENT" | grep -q "max_age:"; then
  log_fail "External MTA-STS missing 'max_age' field"
  VALID=false
fi

if [ "$VALID" = false ]; then
  log_fail "External MTA-STS file is invalid or incomplete"
  log_info "Using internal MTA-STS hosting via Traefik"
  
  if [ "$EXPORT_MODE" = true ]; then
    echo "export MTA_STS_INTERNAL_ENABLED=true"
    echo "export MTA_STS_EXTERNAL_DETECTED=false"
    echo "export MTA_STS_STATUS=internal"
  fi
  exit 1
fi

# External file is valid
log_pass "Valid external MTA-STS file detected!"
log_info "External MTA-STS configuration:"
echo "$EXTERNAL_CONTENT" | sed 's/^/  /' >&2

# Check for potential conflicts
EXTERNAL_MX=$(echo "$EXTERNAL_CONTENT" | grep "mx:" | head -1 | cut -d: -f2- | xargs)
EXPECTED_MX="${SUBDOMAIN}.${DOMAIN}"

if [ "$EXTERNAL_MX" != "$EXPECTED_MX" ]; then
  log_warn "External MTA-STS MX ($EXTERNAL_MX) differs from expected ($EXPECTED_MX)"
  log_warn "Ensure external MTA-STS configuration matches your mail server"
fi

log_info "Disabling internal MTA-STS hosting (using external configuration)"

if [ "$EXPORT_MODE" = true ]; then
  echo "export MTA_STS_INTERNAL_ENABLED=false"
  echo "export MTA_STS_EXTERNAL_DETECTED=true"
  echo "export MTA_STS_STATUS=external"
  echo "export MTA_STS_EXTERNAL_URL=\"$MTA_STS_URL\""
fi

exit 0
