#!/usr/bin/env bash
#
# wait-for-db.sh - Wait for PostgreSQL to be ready
#
# This script robustly waits for PostgreSQL to be fully ready to accept connections
# before proceeding with migrations or other database-dependent operations.
#
# Usage: ./wait-for-db.sh [timeout_seconds]
#
# Exit codes:
#   0 - Database is ready
#   1 - Database failed to become ready within timeout
#   2 - Missing required environment variables

set -euo pipefail

# Configuration
TIMEOUT="${1:-60}"  # Default 60 seconds timeout
RETRY_INTERVAL=2    # Check every 2 seconds

# Note: The SimpleLogin Docker image does not include PostgreSQL client tools
# (pg_isready, psql). This script automatically falls back to using Python/psycopg2
# which is available in the image and provides a more thorough database connection test.

# Parse POSTGRES_HOST and PORT from DB_URI if not set directly
# DB_URI format: postgresql://user:password@host:port/database
if [ -z "${POSTGRES_HOST:-}" ] && [ -n "${DB_URI:-}" ]; then
  POSTGRES_HOST=$(echo "$DB_URI" | sed -n 's|.*@\([^:]*\):.*|\1|p')
fi

if [ -z "${POSTGRES_PORT:-}" ] && [ -n "${DB_URI:-}" ]; then
  POSTGRES_PORT=$(echo "$DB_URI" | sed -n 's|.*:\([0-9]*\)/.*|\1|p')
fi

if [ -z "${POSTGRES_DB:-}" ] && [ -n "${DB_URI:-}" ]; then
  POSTGRES_DB=$(echo "$DB_URI" | sed -n 's|.*/\([^?]*\).*|\1|p')
fi

if [ -z "${POSTGRES_USER:-}" ] && [ -n "${DB_URI:-}" ]; then
  POSTGRES_USER=$(echo "$DB_URI" | sed -n 's|.*://\([^:]*\):.*|\1|p')
fi

if [ -z "${POSTGRES_PASSWORD:-}" ] && [ -n "${DB_URI:-}" ]; then
  POSTGRES_PASSWORD=$(echo "$DB_URI" | sed -n 's|.*://[^:]*:\([^@]*\)@.*|\1|p')
fi

# Set defaults for host and port if still not set
POSTGRES_HOST="${POSTGRES_HOST:-sl-db}"
POSTGRES_PORT="${POSTGRES_PORT:-5432}"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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

# Check required environment variables
check_env_vars() {
  local missing_vars=()
  
  # Check critical variables
  [ -z "${POSTGRES_DB:-}" ] && missing_vars+=("POSTGRES_DB")
  [ -z "${POSTGRES_USER:-}" ] && missing_vars+=("POSTGRES_USER")
  [ -z "${POSTGRES_PASSWORD:-}" ] && missing_vars+=("POSTGRES_PASSWORD")
  
  if [ ${#missing_vars[@]} -gt 0 ]; then
    log_error "Missing required environment variables:"
    for var in "${missing_vars[@]}"; do
      log_error "  - $var"
    done
    log_error ""
    log_error "Please ensure your .env file contains these variables or DB_URI is properly set."
    return 2
  fi
  
  return 0
}

# Wait for PostgreSQL to be ready
wait_for_postgres() {
  local host="${POSTGRES_HOST}"
  local port="${POSTGRES_PORT}"
  local db="${POSTGRES_DB}"
  local user="${POSTGRES_USER}"
  local start_time=$(date +%s)
  local elapsed=0
  
  log_info "Waiting for PostgreSQL to be ready..."
  log_info "Host: $host:$port, Database: $db, User: $user"
  log_info "Timeout: ${TIMEOUT}s, Check interval: ${RETRY_INTERVAL}s"
  
  # Check if pg_isready is available
  local use_python=false
  local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  local python_check_script="$script_dir/check_db_connection.py"
  
  if ! command -v pg_isready &> /dev/null; then
    log_warn "pg_isready not found, using Python/psycopg2 for database checks"
    use_python=true
    
    # Verify Python and psycopg2 are available
    if ! command -v python3 &> /dev/null; then
      log_error "Neither pg_isready nor python3 is available for database connectivity checks"
      return 1
    fi
    
    if ! python3 -c "import psycopg2" 2>/dev/null; then
      log_error "Python3 is available but psycopg2 module is not installed"
      log_error "Cannot perform database connectivity checks without pg_isready or psycopg2"
      return 1
    fi
    
    # Verify check script exists
    if [ ! -f "$python_check_script" ]; then
      log_error "Python check script not found: $python_check_script"
      return 1
    fi
  fi
  
  while [ $elapsed -lt "$TIMEOUT" ]; do
    if [ "$use_python" = true ]; then
      # Use Python script to check database connectivity
      # Password is passed via PGPASSWORD env var to avoid exposure in process listings
      if PGPASSWORD="$POSTGRES_PASSWORD" python3 "$python_check_script" "$host" "$port" "$db" "$user" 2>/dev/null; then
        log_info "PostgreSQL is ready! (verified via Python/psycopg2)"
        return 0
      fi
    else
      # Use pg_isready for database connectivity check
      if PGPASSWORD="$POSTGRES_PASSWORD" pg_isready -h "$host" -p "$port" -U "$user" -d "$db" -t 1 > /dev/null 2>&1; then
        log_info "PostgreSQL is accepting connections"
        
        # Double-check with a simple query if psql is available
        if command -v psql &> /dev/null; then
          if PGPASSWORD="$POSTGRES_PASSWORD" psql -h "$host" -p "$port" -U "$user" -d "$db" -c "SELECT 1;" > /dev/null 2>&1; then
            log_info "Database query test successful"
            log_info "PostgreSQL is ready!"
            return 0
          else
            log_warn "pg_isready succeeded but query failed, retrying..."
          fi
        else
          log_info "PostgreSQL is ready! (pg_isready succeeded, psql not available for query test)"
          return 0
        fi
      fi
    fi
    
    elapsed=$(($(date +%s) - start_time))
    log_info "Waiting... (${elapsed}s/${TIMEOUT}s)"
    sleep "$RETRY_INTERVAL"
  done
  
  log_error "PostgreSQL did not become ready within ${TIMEOUT}s"
  log_error ""
  log_error "Troubleshooting steps:"
  log_error "  1. Check if PostgreSQL container is running:"
  log_error "     docker ps | grep sl-db"
  log_error ""
  log_error "  2. Check PostgreSQL container logs:"
  log_error "     docker logs sl-db"
  log_error ""
  log_error "  3. Verify database configuration in .env file:"
  log_error "     POSTGRES_DB, POSTGRES_USER, POSTGRES_PASSWORD"
  log_error ""
  log_error "  4. Check network connectivity:"
  log_error "     docker compose exec migration ping -c 3 sl-db"
  return 1
}

# Main execution
main() {
  log_info "========================================="
  log_info "Database Readiness Check"
  log_info "========================================="
  
  # Check environment variables
  if ! check_env_vars; then
    exit 2
  fi
  
  # Wait for database
  if ! wait_for_postgres; then
    exit 1
  fi
  
  exit 0
}

# Run main function
main "$@"
