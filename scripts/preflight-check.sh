#!/usr/bin/env bash
#
# preflight-check.sh - Pre-flight validation before starting SimpleLogin
#
# This script validates that all required environment variables are set
# and the system is ready to run the SimpleLogin stack.
#
# Usage: ./preflight-check.sh [.env file path]
#
# Exit codes:
#   0 - All checks passed
#   1 - One or more checks failed

set -euo pipefail

# Default .env file location
ENV_FILE="${1:-.env}"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Counters
PASSED=0
FAILED=0
WARNINGS=0

# Logging functions
log_info() {
  echo -e "${BLUE}[INFO]${NC} $*"
}

log_pass() {
  echo -e "${GREEN}[PASS]${NC} $*"
  ((PASSED++))
}

log_fail() {
  echo -e "${RED}[FAIL]${NC} $*"
  ((FAILED++))
}

log_warn() {
  echo -e "${YELLOW}[WARN]${NC} $*"
  ((WARNINGS++))
}

# Print banner
print_banner() {
  echo ""
  echo "========================================="
  echo "  SimpleLogin Pre-flight Check"
  echo "========================================="
  echo ""
}

# Check if .env file exists
check_env_file() {
  log_info "Checking for .env file..."
  
  if [ ! -f "$ENV_FILE" ]; then
    log_fail ".env file not found at: $ENV_FILE"
    log_info "Please copy .env.example to .env and configure it:"
    log_info "  cp .env.example .env"
    return 1
  fi
  
  log_pass ".env file found"
  return 0
}

# Load .env file
load_env() {
  if [ -f "$ENV_FILE" ]; then
    # Export all variables from .env file
    set -a
    # shellcheck disable=SC1090
    source "$ENV_FILE"
    set +a
  fi
}

# Check required environment variables
check_required_vars() {
  log_info ""
  log_info "Checking required environment variables..."
  
  local all_vars_ok=true
  
  # Critical variables that must be set and not default
  local critical_vars=(
    "DOMAIN:paste-domain-here"
    "POSTGRES_USER:paste-user-here"
    "POSTGRES_PASSWORD:paste-password-here"
    "FLASK_SECRET:paste-flask-secret-here"
  )
  
  for var_def in "${critical_vars[@]}"; do
    local var_name="${var_def%%:*}"
    local default_value="${var_def#*:}"
    local var_value="${!var_name:-}"
    
    if [ -z "$var_value" ]; then
      log_fail "$var_name is not set"
      all_vars_ok=false
    elif [ "$var_value" = "$default_value" ]; then
      log_fail "$var_name still has the default placeholder value"
      log_info "  Please set a real value for $var_name in .env"
      all_vars_ok=false
    else
      log_pass "$var_name is set"
    fi
  done
  
  # Variables that should be set but can have defaults
  local standard_vars=(
    "POSTGRES_DB"
    "SL_VERSION"
    "SL_IMAGE"
    "SUBDOMAIN"
  )
  
  for var in "${standard_vars[@]}"; do
    if [ -z "${!var:-}" ]; then
      log_warn "$var is not set (may use default)"
    else
      log_pass "$var is set: ${!var}"
    fi
  done
  
  if [ "$all_vars_ok" = true ]; then
    return 0
  else
    return 1
  fi
}

# Check Docker installation
check_docker() {
  log_info ""
  log_info "Checking Docker installation..."
  
  if ! command -v docker &> /dev/null; then
    log_fail "Docker is not installed or not in PATH"
    log_info "Please install Docker: https://docs.docker.com/get-docker/"
    return 1
  fi
  
  log_pass "Docker is installed"
  
  # Check if Docker daemon is running
  if ! docker info &> /dev/null; then
    log_fail "Docker daemon is not running"
    log_info "Please start Docker daemon"
    return 1
  fi
  
  log_pass "Docker daemon is running"
  
  # Get Docker version
  local docker_version
  docker_version=$(docker --version | cut -d' ' -f3 | tr -d ',')
  log_info "Docker version: $docker_version"
  
  return 0
}

# Check Docker Compose installation
check_docker_compose() {
  log_info ""
  log_info "Checking Docker Compose installation..."
  
  # Check for docker compose (plugin) or docker-compose (standalone)
  if docker compose version &> /dev/null; then
    log_pass "Docker Compose (plugin) is installed"
    local compose_version
    compose_version=$(docker compose version --short 2>/dev/null || echo "unknown")
    log_info "Docker Compose version: $compose_version"
    return 0
  elif command -v docker-compose &> /dev/null; then
    log_pass "Docker Compose (standalone) is installed"
    local compose_version
    compose_version=$(docker-compose --version | cut -d' ' -f3 | tr -d ',')
    log_info "Docker Compose version: $compose_version"
    return 0
  else
    log_fail "Docker Compose is not installed"
    log_info "Please install Docker Compose: https://docs.docker.com/compose/install/"
    return 1
  fi
}

# Check required files
check_required_files() {
  log_info ""
  log_info "Checking required files..."
  
  local all_files_ok=true
  
  # Check for DKIM key
  if [ ! -f "dkim.key" ]; then
    log_fail "dkim.key not found"
    log_info "Please generate DKIM keys:"
    log_info "  openssl genrsa -traditional -out dkim.key 1024"
    log_info "  openssl rsa -in dkim.key -pubout -out dkim.pub.key"
    all_files_ok=false
  else
    log_pass "dkim.key found"
  fi
  
  if [ ! -f "dkim.pub.key" ]; then
    log_warn "dkim.pub.key not found (optional but recommended)"
  else
    log_pass "dkim.pub.key found"
  fi
  
  # Check for compose files
  local compose_files=(
    "docker-compose.yaml"
    "simple-login-compose.yaml"
    "traefik-compose.yaml"
    "postfix-compose.yaml"
  )
  
  for file in "${compose_files[@]}"; do
    if [ ! -f "$file" ]; then
      log_fail "Required compose file not found: $file"
      all_files_ok=false
    else
      log_pass "$file found"
    fi
  done
  
  if [ "$all_files_ok" = true ]; then
    return 0
  else
    return 1
  fi
}

# Check disk space
check_disk_space() {
  log_info ""
  log_info "Checking disk space..."
  
  local available_gb
  available_gb=$(df -BG . | tail -1 | awk '{print $4}' | sed 's/G//')
  
  if [ "$available_gb" -lt 5 ]; then
    log_warn "Low disk space: ${available_gb}GB available (recommended: 10GB+)"
  else
    log_pass "Sufficient disk space: ${available_gb}GB available"
  fi
  
  return 0
}

# Check network ports
check_ports() {
  log_info ""
  log_info "Checking required ports..."
  
  local ports_ok=true
  local required_ports=(
    "25:SMTP"
    "80:HTTP"
    "443:HTTPS"
    "587:SMTP Submission"
  )
  
  for port_def in "${required_ports[@]}"; do
    local port="${port_def%%:*}"
    local service="${port_def#*:}"
    
    # Check if port is already in use
    if command -v netstat &> /dev/null; then
      if netstat -tuln 2>/dev/null | grep -q ":$port "; then
        log_warn "Port $port ($service) is already in use"
        log_info "This may cause conflicts. Check with: sudo netstat -tuln | grep :$port"
        ports_ok=false
      else
        log_pass "Port $port ($service) is available"
      fi
    elif command -v ss &> /dev/null; then
      if ss -tuln 2>/dev/null | grep -q ":$port "; then
        log_warn "Port $port ($service) is already in use"
        log_info "This may cause conflicts. Check with: sudo ss -tuln | grep :$port"
        ports_ok=false
      else
        log_pass "Port $port ($service) is available"
      fi
    else
      log_warn "Cannot check port $port (netstat/ss not available)"
    fi
  done
  
  return 0
}

# Print summary
print_summary() {
  echo ""
  echo "========================================="
  echo "  Pre-flight Check Summary"
  echo "========================================="
  echo ""
  printf "${GREEN}Passed:${NC}   %d\n" $PASSED
  printf "${YELLOW}Warnings:${NC} %d\n" $WARNINGS
  printf "${RED}Failed:${NC}   %d\n" $FAILED
  echo ""
  
  if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}✓ All critical checks passed!${NC}"
    echo ""
    echo "You can now start SimpleLogin with:"
    echo "  ./up.sh"
    echo ""
    if [ $WARNINGS -gt 0 ]; then
      echo -e "${YELLOW}Note: There are some warnings above. Review them before proceeding.${NC}"
      echo ""
    fi
    return 0
  else
    echo -e "${RED}✗ Some critical checks failed!${NC}"
    echo ""
    echo "Please fix the issues above before starting SimpleLogin."
    echo ""
    return 1
  fi
}

# Main execution
main() {
  print_banner
  
  # Run all checks
  check_env_file || true
  
  # Load environment if file exists
  if [ -f "$ENV_FILE" ]; then
    load_env
  fi
  
  check_required_vars || true
  check_docker || true
  check_docker_compose || true
  check_required_files || true
  check_disk_space || true
  check_ports || true
  
  # Print summary and exit with appropriate code
  if print_summary; then
    exit 0
  else
    exit 1
  fi
}

# Run main function
main "$@"
