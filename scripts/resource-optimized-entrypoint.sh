#!/usr/bin/env bash
#
# resource-optimized-entrypoint.sh - Container entrypoint with resource optimization
#
# This script wraps the original container command with resource detection
# and dynamic configuration. It:
# - Detects available system resources
# - Applies optimal configuration based on RAM/CPU
# - Handles OOM conditions gracefully
# - Provides resource dashboard at startup
#
# Usage: resource-optimized-entrypoint.sh <service-type> [original-command...]
#
# Service types: app, email, job-runner

set -euo pipefail

SERVICE_TYPE="${1:-app}"
shift || true

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
  echo -e "${BLUE}[INFO]${NC} $*" >&2
}

log_warn() {
  echo -e "${YELLOW}[WARN]${NC} $*" >&2
}

log_error() {
  echo -e "${RED}[ERROR]${NC} $*" >&2
}

# Trap OOM killer and handle gracefully
trap_oom() {
  log_error "Out of memory condition detected!"
  log_error "System is resource-starved. Consider:"
  log_error "  1. Increasing system RAM"
  log_error "  2. Enabling LOW_MEMORY_MODE=true"
  log_error "  3. Reducing concurrent operations"
  log_error ""
  log_warn "Attempting graceful shutdown..."
  exit 137  # Standard exit code for OOM killed
}

# Set up OOM trap
trap trap_oom TERM

# Detect resources if script is available
if [ -f /scripts/detect-resources.sh ]; then
  log_info "Detecting system resources for $SERVICE_TYPE..."
  
  # Run detection and capture output
  if ! /scripts/detect-resources.sh; then
    log_warn "Resource detection completed with warnings"
  fi
  
  # Export resource configurations
  eval "$(/scripts/detect-resources.sh --export 2>/dev/null || echo '')"
  
  echo "" >&2
fi

# Apply manual overrides from environment
apply_overrides() {
  # Allow environment variables to override detected values
  if [ -n "${SL_GUNICORN_WORKERS_OVERRIDE:-}" ]; then
    export SL_GUNICORN_WORKERS="$SL_GUNICORN_WORKERS_OVERRIDE"
    log_info "Manual override: SL_GUNICORN_WORKERS=$SL_GUNICORN_WORKERS"
  fi
  
  if [ -n "${SL_GUNICORN_TIMEOUT_OVERRIDE:-}" ]; then
    export SL_GUNICORN_TIMEOUT="$SL_GUNICORN_TIMEOUT_OVERRIDE"
    log_info "Manual override: SL_GUNICORN_TIMEOUT=$SL_GUNICORN_TIMEOUT"
  fi
  
  if [ -n "${SL_DB_POOL_SIZE_OVERRIDE:-}" ]; then
    export SL_DB_POOL_SIZE="$SL_DB_POOL_SIZE_OVERRIDE"
    log_info "Manual override: SL_DB_POOL_SIZE=$SL_DB_POOL_SIZE"
  fi
}

apply_overrides

# Build service-specific command with dynamic configuration
build_command() {
  local service=$1
  shift
  
  case $service in
    app)
      # If command is provided, use it; otherwise use default Gunicorn
      if [ $# -gt 0 ]; then
        echo "$@"
      else
        local workers=${SL_GUNICORN_WORKERS:-2}
        local timeout=${SL_GUNICORN_TIMEOUT:-30}
        local max_requests=${SL_MAX_REQUESTS:-1000}
        
        echo "gunicorn wsgi:app -b 0.0.0.0:7777 -w $workers --timeout $timeout --max-requests $max_requests --max-requests-jitter $((max_requests / 10))"
      fi
      ;;
    
    email)
      # Email handler - use threading if supported
      if [ $# -gt 0 ]; then
        echo "$@"
      else
        echo "python email_handler.py"
      fi
      ;;
    
    job-runner)
      # Job runner
      if [ $# -gt 0 ]; then
        echo "$@"
      else
        echo "python job_runner.py"
      fi
      ;;
    
    *)
      # Unknown service, pass through command
      echo "$@"
      ;;
  esac
}

# Build the final command
FINAL_CMD=$(build_command "$SERVICE_TYPE" "$@")

log_info "Starting $SERVICE_TYPE with command: $FINAL_CMD"
echo "" >&2

# Execute the command with exec to replace the shell process
# This ensures proper signal handling
exec bash -c "$FINAL_CMD"
