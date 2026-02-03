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
    # Parse .env file more carefully, avoiding bash syntax errors
    # Only export simple VAR=value lines, skip arrays and complex syntax
    while IFS= read -r line || [ -n "$line" ]; do
      # Skip comments and empty lines
      if [[ "$line" =~ ^[[:space:]]*# ]] || [[ -z "$line" ]]; then
        continue
      fi
      
      # Only process simple VAR=value lines (no arrays or complex expressions)
      if [[ "$line" =~ ^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
        var_name="${BASH_REMATCH[1]}"
        var_value="${BASH_REMATCH[2]}"
        
        # Skip lines with array syntax or function calls
        if [[ "$var_value" =~ ^\[.*\]$ ]] || [[ "$var_value" =~ \$\( ]]; then
          continue
        fi
        
        # Export the variable
        export "${var_name}=${var_value}"
      fi
    done < "$ENV_FILE"
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
  
  # Check for scripts directory and required scripts
  if [ ! -d "scripts" ]; then
    log_fail "scripts directory not found"
    log_info "The scripts directory is required for Docker Compose mounts"
    log_info "Ensure you're running from the repository root"
    all_files_ok=false
  else
    log_pass "scripts directory found"
    
    # Check for traefik-entrypoint.sh
    if [ ! -f "scripts/traefik-entrypoint.sh" ]; then
      log_fail "scripts/traefik-entrypoint.sh not found"
      log_info "This script is required for Traefik to start properly"
      log_info "It should be mounted into the Traefik container at /scripts/traefik-entrypoint.sh"
      all_files_ok=false
    else
      log_pass "scripts/traefik-entrypoint.sh found"
      
      # Check if the script is executable
      if [ ! -x "scripts/traefik-entrypoint.sh" ]; then
        log_warn "scripts/traefik-entrypoint.sh is not executable"
        log_info "Making it executable with: chmod +x scripts/traefik-entrypoint.sh"
        chmod +x scripts/traefik-entrypoint.sh 2>/dev/null && log_pass "Made script executable" || log_fail "Failed to make script executable"
      else
        log_pass "scripts/traefik-entrypoint.sh is executable"
      fi
    fi
  fi
  
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

# Check system resources
check_system_resources() {
  log_info ""
  log_info "Checking system resources..."
  
  # Check if detect-resources.sh exists
  if [ ! -f "scripts/detect-resources.sh" ]; then
    log_warn "Resource detection script not found (optional)"
    return 0
  fi
  
  # Run resource detection
  if bash scripts/detect-resources.sh > /dev/null 2>&1; then
    log_pass "Resource detection completed"
    
    # Get RAM info
    if [ -f /proc/meminfo ]; then
      local total_ram_kb=$(awk '/MemTotal/ {print $2}' /proc/meminfo)
      local total_ram_mb=$((total_ram_kb / 1024))
      
      if [ "$total_ram_mb" -lt 256 ]; then
        log_fail "Insufficient RAM: ${total_ram_mb}MB (minimum: 512MB)"
        log_info "SimpleLogin requires at least 512MB RAM to function properly"
        return 1
      elif [ "$total_ram_mb" -lt 512 ]; then
        log_warn "Low RAM: ${total_ram_mb}MB detected"
        log_info "System will run in degraded mode. Consider enabling LOW_MEMORY_MODE=true"
        log_info "For guidance, see LOW_RESOURCE_GUIDE.md"
      elif [ "$total_ram_mb" -lt 1024 ]; then
        log_info "RAM: ${total_ram_mb}MB - Basic mode (consider 1GB+ for better performance)"
      else
        log_pass "RAM: ${total_ram_mb}MB - Sufficient"
      fi
    fi
  else
    log_warn "Resource detection completed with warnings"
    log_info "Check scripts/detect-resources.sh output for details"
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

# Check MTA-STS configuration
check_mta_sts() {
  log_info ""
  log_info "Checking MTA-STS configuration..."
  
  local mta_sts_mode="${MTA_STS_MODE:-auto}"
  
  # Validate MTA_STS_MODE
  case "$mta_sts_mode" in
    auto|internal|external|disabled)
      log_pass "MTA_STS_MODE is set to: $mta_sts_mode"
      ;;
    *)
      log_fail "Invalid MTA_STS_MODE: $mta_sts_mode"
      log_info "Must be one of: auto, internal, external, disabled"
      return 1
      ;;
  esac
  
  # Check if detection script exists
  if [ ! -f "scripts/detect-mta-sts.sh" ]; then
    log_warn "MTA-STS detection script not found (scripts/detect-mta-sts.sh)"
    return 0
  fi
  
  # Run MTA-STS detection if mode is auto
  if [ "$mta_sts_mode" = "auto" ] && [ -n "${DOMAIN:-}" ]; then
    log_info "Running MTA-STS auto-detection..."
    
    if bash scripts/detect-mta-sts.sh "${DOMAIN}" > /dev/null 2>&1; then
      log_pass "MTA-STS detection completed successfully"
    else
      log_info "External MTA-STS not found, will use internal hosting"
    fi
  elif [ "$mta_sts_mode" = "external" ]; then
    log_info "MTA-STS mode is 'external' - ensure external hosting is configured"
    log_warn "No validation performed for external MTA-STS configuration"
  elif [ "$mta_sts_mode" = "disabled" ]; then
    log_warn "MTA-STS is disabled (not recommended for production)"
  fi
  
  # Warn about DNS requirements
  if [ "$mta_sts_mode" != "disabled" ] && [ -n "${DOMAIN:-}" ]; then
    log_info "MTA-STS requires the following DNS records:"
    log_info "  1. A record: mta-sts.${DOMAIN} -> your server IP"
    log_info "  2. TXT record: _mta-sts.${DOMAIN} -> v=STSv1; id=<timestamp>"
    log_info "See README.md for detailed DNS configuration"
  fi
  
  return 0
}

# Check Cloudflare DNS credentials for DNS-01 certificate issuance
check_cloudflare_dns() {
  log_info ""
  log_info "Checking DNS-01 certificate configuration..."
  
  # Check if Python script exists
  if [ ! -f "scripts/check-cloudflare-dns.py" ]; then
    log_warn "Cloudflare DNS check script not found (scripts/check-cloudflare-dns.py)"
    return 0
  fi
  
  # Check if Python 3 is available
  if ! command -v python3 &> /dev/null; then
    log_warn "Python 3 not available - skipping Cloudflare DNS check"
    return 0
  fi
  
  # Run the Cloudflare DNS pre-flight check
  # This script will:
  #   - Check if DNS-01 challenge is configured
  #   - Check if valid certificates already exist (skip API test if so)
  #   - Validate Cloudflare credentials if needed
  #   - Test Cloudflare API connectivity if needed
  #
  # The script is silent (exit 0) if:
  #   - DNS-01 is not configured
  #   - Cloudflare is not the DNS provider
  #   - Valid certificates already exist
  #
  # The script only performs checks when DNS-01 + Cloudflare is configured
  # and certificates are missing or expired.
  
  if python3 scripts/check-cloudflare-dns.py --env-file "$ENV_FILE" 2>&1; then
    # Check passed (or was skipped due to not using DNS-01/Cloudflare)
    return 0
  else
    # Check failed - error messages already printed by Python script
    log_fail "DNS-01 certificate pre-flight check failed"
    log_info "See error messages above for remediation steps"
    return 1
  fi
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
  check_system_resources || true
  check_disk_space || true
  check_ports || true
  check_mta_sts || true
  check_cloudflare_dns || true
  
  # Print summary and exit with appropriate code
  if print_summary; then
    exit 0
  else
    exit 1
  fi
}

# Run main function
main "$@"
