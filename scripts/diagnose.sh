#!/usr/bin/env bash
#
# diagnose.sh - Collect diagnostic information for troubleshooting
#
# This script collects comprehensive diagnostic information about
# the SimpleLogin deployment to help troubleshoot issues.
#
# Usage: ./diagnose.sh [output-file]
#
# Exit codes:
#   0 - Diagnostics collected successfully
#   1 - Error collecting diagnostics

set -euo pipefail

# Default output file
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
OUTPUT_FILE="${1:-simplelogin-diagnostics-${TIMESTAMP}.log}"

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

log_error() {
  echo -e "${RED}[ERROR]${NC} $*" >&2
}

log_section() {
  echo -e "${BLUE}[SECTION]${NC} $*"
}

# Print to both console and file
print_to_file() {
  echo "$@" | tee -a "$OUTPUT_FILE"
}

# Print section header
print_section() {
  local title="$1"
  {
    echo ""
    echo "========================================="
    echo "  $title"
    echo "========================================="
    echo ""
  } | tee -a "$OUTPUT_FILE"
}

# Collect system information
collect_system_info() {
  log_section "Collecting system information..."
  print_section "SYSTEM INFORMATION"
  
  {
    echo "Hostname: $(hostname)"
    echo "Date: $(date)"
    echo "Uptime: $(uptime)"
    echo ""
    
    if command -v uname &> /dev/null; then
      echo "Kernel: $(uname -a)"
      echo ""
    fi
    
    echo "Disk Usage:"
    df -h
    echo ""
    
    echo "Memory Usage:"
    free -h || true
    echo ""
  } >> "$OUTPUT_FILE" 2>&1
}

# Collect Docker information
collect_docker_info() {
  log_section "Collecting Docker information..."
  print_section "DOCKER INFORMATION"
  
  {
    if command -v docker &> /dev/null; then
      echo "Docker Version:"
      docker --version
      echo ""
      
      echo "Docker Compose Version:"
      if docker compose version &> /dev/null; then
        docker compose version
      elif command -v docker-compose &> /dev/null; then
        docker-compose --version
      else
        echo "Docker Compose not found"
      fi
      echo ""
      
      echo "Docker Info:"
      docker info 2>&1 || echo "Failed to get Docker info"
      echo ""
    else
      echo "Docker command not found"
      echo ""
    fi
  } >> "$OUTPUT_FILE" 2>&1
}

# Collect container status
collect_container_status() {
  log_section "Collecting container status..."
  print_section "CONTAINER STATUS"
  
  {
    echo "All Containers:"
    docker ps -a 2>&1 || echo "Failed to list containers"
    echo ""
    
    echo "SimpleLogin Containers:"
    docker ps -a --filter "name=sl-" 2>&1 || echo "No SimpleLogin containers found"
    echo ""
    
    echo "Postfix Container:"
    docker ps -a --filter "name=postfix" 2>&1 || echo "Postfix container not found"
    echo ""
    
    echo "Traefik Container:"
    docker ps -a --filter "name=traefik" 2>&1 || echo "Traefik container not found"
    echo ""
  } >> "$OUTPUT_FILE" 2>&1
}

# Collect container logs
collect_container_logs() {
  log_section "Collecting container logs..."
  print_section "CONTAINER LOGS"
  
  local containers=(
    "sl-migration"
    "sl-db"
    "sl-init"
    "sl-app"
    "sl-email"
    "sl-job-runner"
    "postfix"
    "traefik"
  )
  
  for container in "${containers[@]}"; do
    {
      echo ""
      echo "-----------------------------------------"
      echo "Logs for: $container"
      echo "-----------------------------------------"
      echo ""
      
      if docker ps -a --format '{{.Names}}' | grep -q "^${container}$"; then
        docker logs --tail=100 "$container" 2>&1 || echo "Failed to get logs for $container"
      else
        echo "Container $container not found or not running"
      fi
      echo ""
    } >> "$OUTPUT_FILE" 2>&1
  done
}

# Collect Docker Compose configuration
collect_compose_config() {
  log_section "Collecting Docker Compose configuration..."
  print_section "DOCKER COMPOSE CONFIGURATION"
  
  {
    if [ -f "docker-compose.yaml" ]; then
      echo "docker-compose.yaml:"
      cat docker-compose.yaml
      echo ""
    fi
    
    if [ -f "simple-login-compose.yaml" ]; then
      echo "simple-login-compose.yaml:"
      cat simple-login-compose.yaml
      echo ""
    fi
    
    echo "Parsed Compose Configuration:"
    docker compose config 2>&1 || echo "Failed to parse compose configuration"
    echo ""
  } >> "$OUTPUT_FILE" 2>&1
}

# Collect environment configuration (sanitized)
collect_env_config() {
  log_section "Collecting environment configuration (sanitized)..."
  print_section "ENVIRONMENT CONFIGURATION (SANITIZED)"
  
  {
    if [ -f ".env" ]; then
      echo "Environment variables (passwords hidden):"
      # Print .env but hide sensitive values
      while IFS= read -r line; do
        if [[ "$line" =~ ^[[:space:]]*# ]] || [[ -z "$line" ]]; then
          echo "$line"
        elif [[ "$line" =~ PASSWORD|SECRET|KEY|TOKEN ]]; then
          var_name="${line%%=*}"
          echo "${var_name}=***HIDDEN***"
        else
          echo "$line"
        fi
      done < .env
      echo ""
    else
      echo ".env file not found"
      echo ""
    fi
  } >> "$OUTPUT_FILE" 2>&1
}

# Collect network information
collect_network_info() {
  log_section "Collecting network information..."
  print_section "NETWORK INFORMATION"
  
  {
    echo "Docker Networks:"
    docker network ls 2>&1 || echo "Failed to list networks"
    echo ""
    
    echo "Network inspect for 'traefik' network:"
    docker network inspect traefik 2>&1 || echo "Traefik network not found"
    echo ""
    
    echo "Port bindings:"
    if command -v netstat &> /dev/null; then
      netstat -tuln | grep -E ':(25|80|443|587|5432|7777) ' 2>&1 || echo "No matching ports found"
    elif command -v ss &> /dev/null; then
      ss -tuln | grep -E ':(25|80|443|587|5432|7777) ' 2>&1 || echo "No matching ports found"
    else
      echo "netstat/ss not available"
    fi
    echo ""
  } >> "$OUTPUT_FILE" 2>&1
}

# Collect volume information
collect_volume_info() {
  log_section "Collecting volume information..."
  print_section "VOLUME INFORMATION"
  
  {
    echo "Docker Volumes:"
    docker volume ls 2>&1 || echo "Failed to list volumes"
    echo ""
    
    echo "Local directories:"
    for dir in db pgp upload; do
      if [ -d "$dir" ]; then
        echo "Directory: $dir"
        ls -lah "$dir" 2>&1 || echo "Cannot list $dir"
        echo ""
      else
        echo "Directory $dir does not exist"
        echo ""
      fi
    done
  } >> "$OUTPUT_FILE" 2>&1
}

# Collect file existence check
collect_file_check() {
  log_section "Collecting file existence check..."
  print_section "FILE EXISTENCE CHECK"
  
  {
    local files=(
      ".env"
      "docker-compose.yaml"
      "simple-login-compose.yaml"
      "traefik-compose.yaml"
      "postfix-compose.yaml"
      "dkim.key"
      "dkim.pub.key"
    )
    
    for file in "${files[@]}"; do
      if [ -f "$file" ]; then
        echo "✓ $file exists"
      else
        echo "✗ $file NOT FOUND"
      fi
    done
    echo ""
  } >> "$OUTPUT_FILE" 2>&1
}

# Check database connectivity
check_database() {
  log_section "Checking database connectivity..."
  print_section "DATABASE CONNECTIVITY CHECK"
  
  {
    if docker ps --format '{{.Names}}' | grep -q "^sl-db$"; then
      echo "PostgreSQL container is running"
      echo ""
      
      # Try to check if database is accepting connections
      if [ -f ".env" ]; then
        # shellcheck disable=SC1091
        source .env
        
        echo "Attempting to connect to database..."
        docker compose exec -T postgres \
          sh -c "PGPASSWORD='$POSTGRES_PASSWORD' pg_isready -U '$POSTGRES_USER' -d '$POSTGRES_DB' -h 127.0.0.1 -p 5432" 2>&1 \
          || echo "Database connection check failed"
        echo ""
      fi
    else
      echo "PostgreSQL container is not running"
      echo ""
    fi
  } >> "$OUTPUT_FILE" 2>&1
}

# Print summary and next steps
print_summary() {
  log_info ""
  log_info "Diagnostics collection complete!"
  log_info "Output saved to: $OUTPUT_FILE"
  log_info ""
  log_info "Next steps:"
  log_info "  1. Review the diagnostic file: less $OUTPUT_FILE"
  log_info "  2. Look for ERROR or FAILED messages"
  log_info "  3. Check container logs for stack traces"
  log_info "  4. Verify environment configuration"
  log_info ""
  log_info "If you need help, please share this file (after removing any sensitive data)"
  log_info ""
}

# Main execution
main() {
  echo ""
  echo "========================================="
  echo "  SimpleLogin Diagnostic Collection"
  echo "========================================="
  echo ""
  
  log_info "Starting diagnostic collection..."
  log_info "Output file: $OUTPUT_FILE"
  echo ""
  
  # Initialize output file
  {
    echo "SimpleLogin Diagnostics Report"
    echo "Generated: $(date)"
    echo "Hostname: $(hostname)"
  } > "$OUTPUT_FILE"
  
  # Collect all diagnostic information
  collect_system_info
  collect_docker_info
  collect_container_status
  collect_env_config
  collect_compose_config
  collect_network_info
  collect_volume_info
  collect_file_check
  check_database
  collect_container_logs
  
  # Print summary
  print_summary
  
  exit 0
}

# Run main function
main "$@"
