#!/usr/bin/env bash
#
# run-migration.sh - Run database migrations with proper error handling
#
# This script orchestrates the database migration process:
#   1. Waits for the database to be ready
#   2. Runs Alembic migrations
#   3. Captures and logs errors with actionable troubleshooting steps
#
# Usage: ./run-migration.sh
#
# Exit codes:
#   0 - Migration completed successfully
#   1 - Migration failed
#   2 - Database not ready
#   3 - Configuration error

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
  echo -e "${GREEN}[INFO]${NC} $*"
}

log_warn() {
  echo -e "${YELLOW}[WARN]${NC} $*"
}

log_error() {
  echo -e "${RED}[ERROR]${NC} $*" >&2
}

log_debug() {
  echo -e "${BLUE}[DEBUG]${NC} $*"
}

# Print banner
print_banner() {
  echo ""
  echo "========================================="
  echo "  SimpleLogin Database Migration"
  echo "========================================="
  echo ""
}

# Check critical environment variables
check_config() {
  log_info "Checking configuration..."
  
  local missing_vars=()
  local critical_vars=(
    "DB_URI"
    "POSTGRES_DB"
    "POSTGRES_USER"
    "POSTGRES_PASSWORD"
  )
  
  for var in "${critical_vars[@]}"; do
    if [ -z "${!var:-}" ]; then
      missing_vars+=("$var")
    fi
  done
  
  if [ ${#missing_vars[@]} -gt 0 ]; then
    log_error "Configuration error: Missing required environment variables"
    for var in "${missing_vars[@]}"; do
      log_error "  - $var"
    done
    log_error ""
    log_error "Please check your .env file and ensure all required variables are set."
    return 3
  fi
  
  log_info "Configuration check passed"
  return 0
}

# Wait for database to be ready
wait_for_database() {
  log_info "Step 1/2: Checking database connectivity..."
  
  if [ -f "$SCRIPT_DIR/wait-for-db.sh" ]; then
    if bash "$SCRIPT_DIR/wait-for-db.sh" 60; then
      return 0
    else
      log_error "Database readiness check failed"
      return 2
    fi
  else
    log_warn "wait-for-db.sh not found, using basic wait..."
    sleep 5
    return 0
  fi
}

# Run Alembic migration
run_migration() {
  log_info "Step 2/2: Running Alembic migrations..."
  log_info "Command: alembic upgrade head"
  echo ""
  
  # Create a temporary log file
  local migration_log="/tmp/migration-$$.log"
  
  # Run migration and capture output
  if alembic upgrade head 2>&1 | tee "$migration_log"; then
    log_info ""
    log_info "✓ Migration completed successfully!"
    
    # Create success marker file for healthcheck
    touch /tmp/migration-complete
    
    rm -f "$migration_log"
    return 0
  else
    local exit_code=$?
    log_error ""
    log_error "✗ Migration failed with exit code: $exit_code"
    
    # Analyze error and provide helpful messages
    analyze_migration_error "$migration_log"
    
    rm -f "$migration_log"
    return 1
  fi
}

# Analyze migration errors and provide troubleshooting guidance
analyze_migration_error() {
  local log_file="$1"
  
  log_error ""
  log_error "Migration Error Analysis:"
  log_error "=========================="
  
  # Check for common error patterns
  if grep -qi "could not connect" "$log_file" 2>/dev/null; then
    log_error "Issue: Database connection failed"
    log_error ""
    log_error "Possible causes:"
    log_error "  1. Database container is not running"
    log_error "  2. Incorrect database credentials in .env"
    log_error "  3. Network connectivity issues"
    log_error ""
    log_error "Troubleshooting steps:"
    log_error "  • Check database status: docker ps | grep sl-db"
    log_error "  • Check database logs: docker logs sl-db"
    log_error "  • Verify DB_URI in .env file"
    
  elif grep -qi "password authentication failed" "$log_file" 2>/dev/null; then
    log_error "Issue: Database authentication failed"
    log_error ""
    log_error "Troubleshooting steps:"
    log_error "  • Verify POSTGRES_USER and POSTGRES_PASSWORD in .env"
    log_error "  • Ensure they match what was used to initialize the database"
    log_error "  • If this is a fresh install, remove db/ folder and restart"
    
  elif grep -qi "relation.*does not exist" "$log_file" 2>/dev/null; then
    log_error "Issue: Database schema issue"
    log_error ""
    log_error "Troubleshooting steps:"
    log_error "  • This might be a database corruption or version mismatch"
    log_error "  • Check SimpleLogin version: SL_VERSION in .env"
    log_error "  • Review migration history: alembic current"
    
  elif grep -qi "version.*conflicts" "$log_file" 2>/dev/null; then
    log_error "Issue: Alembic version conflict"
    log_error ""
    log_error "Troubleshooting steps:"
    log_error "  • Database might be from a different version"
    log_error "  • Check current Alembic revision: alembic current"
    log_error "  • Check target revision: alembic heads"
    
  else
    log_error "Issue: Unknown migration error"
    log_error ""
    log_error "Please review the full error output above."
  fi
  
  log_error ""
  log_error "For more help, run: bash scripts/diagnose.sh"
  log_error "This will collect diagnostic information to help troubleshoot the issue."
}

# Main execution
main() {
  print_banner
  
  # Check configuration
  if ! check_config; then
    exit 3
  fi
  
  # Wait for database
  if ! wait_for_database; then
    log_error "Cannot proceed with migration: database is not ready"
    exit 2
  fi
  
  echo ""
  
  # Run migration
  if ! run_migration; then
    log_error ""
    log_error "Migration process failed. Please review the errors above."
    exit 1
  fi
  
  echo ""
  log_info "========================================="
  log_info "Migration process completed successfully"
  log_info "========================================="
  echo ""
  
  exit 0
}

# Run main function
main "$@"
