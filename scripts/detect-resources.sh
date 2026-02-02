#!/usr/bin/env bash
#
# detect-resources.sh - Detect system resources and calculate optimal configurations
#
# This script detects available system resources (RAM, CPU) and calculates
# optimal configuration values for running SimpleLogin on resource-constrained systems.
#
# Usage: ./detect-resources.sh [--export] [--json]
#
# Options:
#   --export   Export configuration as environment variables
#   --json     Output configuration as JSON
#
# Exit codes:
#   0 - Success
#   1 - Critical resource shortage (< 256MB RAM)

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# Configuration thresholds (in MB)
CRITICAL_RAM=256
LOW_RAM=768
MEDIUM_RAM=2048
HIGH_RAM=4096

# Parse command line arguments
EXPORT_MODE=false
JSON_MODE=false

for arg in "$@"; do
  case $arg in
    --export)
      EXPORT_MODE=true
      shift
      ;;
    --json)
      JSON_MODE=true
      shift
      ;;
  esac
done

# Detect total RAM in MB
detect_total_ram() {
  if [ -f /proc/meminfo ]; then
    awk '/MemTotal/ {printf "%.0f", $2/1024}' /proc/meminfo
  else
    # Fallback for systems without /proc/meminfo
    echo "1024"
  fi
}

# Detect available RAM in MB
detect_available_ram() {
  if [ -f /proc/meminfo ]; then
    awk '/MemAvailable/ {printf "%.0f", $2/1024}' /proc/meminfo
  else
    # Fallback - assume 70% of total is available
    local total
    total=$(detect_total_ram)
    echo $((total * 70 / 100))
  fi
}

# Detect CPU cores
detect_cpu_cores() {
  if command -v nproc &> /dev/null; then
    nproc
  elif [ -f /proc/cpuinfo ]; then
    grep -c ^processor /proc/cpuinfo
  else
    # Fallback
    echo "1"
  fi
}

# Calculate optimal Gunicorn workers
# Formula: (2 * CPU_CORES) + 1, but limited by available RAM
calculate_gunicorn_workers() {
  local total_ram=$1
  local cpu_cores=$2
  local workers
  
  # Base calculation: (2 * CPU) + 1
  workers=$((2 * cpu_cores + 1))
  
  # Adjust based on RAM availability
  # Each worker needs approximately 100-150MB
  if [ "$total_ram" -lt 512 ]; then
    workers=1
  elif [ "$total_ram" -lt 768 ]; then
    workers=2
  elif [ "$total_ram" -lt 1024 ]; then
    workers=$((workers < 2 ? workers : 2))
  elif [ "$total_ram" -lt 2048 ]; then
    workers=$((workers < 3 ? workers : 3))
  else
    # Cap at reasonable maximum
    workers=$((workers < 8 ? workers : 8))
  fi
  
  echo "$workers"
}

# Calculate Gunicorn timeout
calculate_gunicorn_timeout() {
  local total_ram=$1
  
  if [ "$total_ram" -lt 512 ]; then
    echo "120"  # Longer timeout for slow systems
  elif [ "$total_ram" -lt 1024 ]; then
    echo "90"
  elif [ "$total_ram" -lt 2048 ]; then
    echo "60"
  else
    echo "30"
  fi
}

# Calculate max requests per worker (for memory leak protection)
calculate_max_requests() {
  local total_ram=$1
  
  if [ "$total_ram" -lt 512 ]; then
    echo "100"   # Recycle workers more frequently on low RAM
  elif [ "$total_ram" -lt 1024 ]; then
    echo "500"
  elif [ "$total_ram" -lt 2048 ]; then
    echo "1000"
  else
    echo "2000"
  fi
}

# Calculate database pool size
calculate_db_pool_size() {
  local total_ram=$1
  local workers=$2
  
  # Database pool should be at least as large as workers
  # but not too large on low-RAM systems
  local pool_size=$((workers + 2))
  
  if [ "$total_ram" -lt 512 ]; then
    pool_size=3
  elif [ "$total_ram" -lt 1024 ]; then
    pool_size=$((pool_size < 5 ? pool_size : 5))
  elif [ "$total_ram" -lt 2048 ]; then
    pool_size=$((pool_size < 10 ? pool_size : 10))
  else
    pool_size=$((pool_size < 20 ? pool_size : 20))
  fi
  
  echo "$pool_size"
}

# Calculate email handler threads
calculate_email_threads() {
  local total_ram=$1
  local cpu_cores=$2
  
  local threads=$cpu_cores
  
  if [ "$total_ram" -lt 512 ]; then
    threads=1
  elif [ "$total_ram" -lt 1024 ]; then
    threads=$((threads < 2 ? threads : 2))
  else
    threads=$((threads < 4 ? threads : 4))
  fi
  
  echo "$threads"
}

# Calculate job runner threads
calculate_job_threads() {
  local total_ram=$1
  local cpu_cores=$2
  
  local threads=$cpu_cores
  
  if [ "$total_ram" -lt 512 ]; then
    threads=1
  elif [ "$total_ram" -lt 1024 ]; then
    threads=$((threads < 2 ? threads : 2))
  else
    threads=$((threads < 3 ? threads : 3))
  fi
  
  echo "$threads"
}

# Determine RAM tier for display
get_ram_tier() {
  local total_ram=$1
  
  if [ "$total_ram" -lt "$CRITICAL_RAM" ]; then
    echo "CRITICAL"
  elif [ "$total_ram" -lt "$LOW_RAM" ]; then
    echo "LOW"
  elif [ "$total_ram" -lt "$MEDIUM_RAM" ]; then
    echo "MEDIUM"
  elif [ "$total_ram" -lt "$HIGH_RAM" ]; then
    echo "HIGH"
  else
    echo "OPTIMAL"
  fi
}

# Main detection function
detect_and_configure() {
  # Detect resources
  local total_ram
  local available_ram
  local cpu_cores
  
  total_ram=$(detect_total_ram)
  available_ram=$(detect_available_ram)
  cpu_cores=$(detect_cpu_cores)
  
  # Check for forced low-memory mode
  local forced_low_memory=${LOW_MEMORY_MODE:-false}
  if [ "$forced_low_memory" = "true" ] || [ "$forced_low_memory" = "1" ]; then
    total_ram=512  # Force low-memory calculations
    available_ram=400
  fi
  
  # Calculate configurations
  local gunicorn_workers
  local gunicorn_timeout
  local max_requests
  local db_pool_size
  local email_threads
  local job_threads
  local ram_tier
  
  gunicorn_workers=$(calculate_gunicorn_workers "$total_ram" "$cpu_cores")
  gunicorn_timeout=$(calculate_gunicorn_timeout "$total_ram")
  max_requests=$(calculate_max_requests "$total_ram")
  db_pool_size=$(calculate_db_pool_size "$total_ram" "$gunicorn_workers")
  email_threads=$(calculate_email_threads "$total_ram" "$cpu_cores")
  job_threads=$(calculate_job_threads "$total_ram" "$cpu_cores")
  ram_tier=$(get_ram_tier "$total_ram")
  
  # Output based on mode
  if [ "$JSON_MODE" = true ]; then
    # JSON output
    cat <<EOF
{
  "system": {
    "total_ram_mb": $total_ram,
    "available_ram_mb": $available_ram,
    "cpu_cores": $cpu_cores,
    "ram_tier": "$ram_tier",
    "low_memory_mode": $forced_low_memory
  },
  "configuration": {
    "gunicorn_workers": $gunicorn_workers,
    "gunicorn_timeout": $gunicorn_timeout,
    "max_requests_per_worker": $max_requests,
    "db_pool_size": $db_pool_size,
    "email_handler_threads": $email_threads,
    "job_runner_threads": $job_threads
  }
}
EOF
  elif [ "$EXPORT_MODE" = true ]; then
    # Export as environment variables
    export SL_GUNICORN_WORKERS="$gunicorn_workers"
    export SL_GUNICORN_TIMEOUT="$gunicorn_timeout"
    export SL_MAX_REQUESTS="$max_requests"
    export SL_DB_POOL_SIZE="$db_pool_size"
    export SL_EMAIL_THREADS="$email_threads"
    export SL_JOB_THREADS="$job_threads"
    
    echo "export SL_GUNICORN_WORKERS=$gunicorn_workers"
    echo "export SL_GUNICORN_TIMEOUT=$gunicorn_timeout"
    echo "export SL_MAX_REQUESTS=$max_requests"
    echo "export SL_DB_POOL_SIZE=$db_pool_size"
    echo "export SL_EMAIL_THREADS=$email_threads"
    echo "export SL_JOB_THREADS=$job_threads"
  else
    # Human-readable dashboard
    print_resource_dashboard "$total_ram" "$available_ram" "$cpu_cores" \
      "$ram_tier" "$forced_low_memory" "$gunicorn_workers" "$gunicorn_timeout" \
      "$max_requests" "$db_pool_size" "$email_threads" "$job_threads"
  fi
  
  # Return warning/error code if RAM is critically low
  if [ "$total_ram" -lt "$CRITICAL_RAM" ]; then
    return 1
  fi
  
  return 0
}

# Print resource dashboard
print_resource_dashboard() {
  local total_ram=$1
  local available_ram=$2
  local cpu_cores=$3
  local ram_tier=$4
  local forced_low_memory=$5
  local gunicorn_workers=$6
  local gunicorn_timeout=$7
  local max_requests=$8
  local db_pool_size=$9
  local email_threads=${10}
  local job_threads=${11}
  
  echo ""
  echo "╔════════════════════════════════════════════════════════════════╗"
  echo "║      SimpleLogin Dynamic Resource Optimization Dashboard       ║"
  echo "╚════════════════════════════════════════════════════════════════╝"
  echo ""
  
  # System Resources Section
  echo -e "${CYAN}━━━ SYSTEM RESOURCES ━━━${NC}"
  echo ""
  printf "  ${BLUE}Total RAM:${NC}        %6d MB" "$total_ram"
  
  # Color code based on RAM tier
  case $ram_tier in
    CRITICAL)
      echo -e "  ${RED}[CRITICAL - INSUFFICIENT]${NC}"
      ;;
    LOW)
      echo -e "  ${YELLOW}[LOW - DEGRADED MODE]${NC}"
      ;;
    MEDIUM)
      echo -e "  ${GREEN}[MEDIUM - BASIC MODE]${NC}"
      ;;
    HIGH)
      echo -e "  ${GREEN}[HIGH - GOOD]${NC}"
      ;;
    OPTIMAL)
      echo -e "  ${GREEN}[OPTIMAL]${NC}"
      ;;
  esac
  
  printf "  ${BLUE}Available RAM:${NC}    %6d MB\n" "$available_ram"
  printf "  ${BLUE}CPU Cores:${NC}        %6d\n" "$cpu_cores"
  
  if [ "$forced_low_memory" = "true" ] || [ "$forced_low_memory" = "1" ]; then
    echo -e "  ${YELLOW}Mode:${NC}             FORCED LOW-MEMORY MODE"
  fi
  
  echo ""
  
  # Dynamic Configuration Section
  echo -e "${CYAN}━━━ DYNAMIC CONFIGURATION ━━━${NC}"
  echo ""
  echo -e "${MAGENTA}Web Application (Gunicorn):${NC}"
  printf "  Workers:              %2d\n" "$gunicorn_workers"
  printf "  Timeout:              %3d seconds\n" "$gunicorn_timeout"
  printf "  Max Requests/Worker:  %4d\n" "$max_requests"
  echo ""
  
  echo -e "${MAGENTA}Database:${NC}"
  printf "  Connection Pool Size: %2d\n" "$db_pool_size"
  echo ""
  
  echo -e "${MAGENTA}Background Services:${NC}"
  printf "  Email Handler Threads: %2d\n" "$email_threads"
  printf "  Job Runner Threads:    %2d\n" "$job_threads"
  echo ""
  
  # Warnings Section
  if [ "$total_ram" -lt "$CRITICAL_RAM" ]; then
    echo -e "${RED}━━━ CRITICAL WARNING ━━━${NC}"
    echo ""
    echo -e "${RED}⚠ System has insufficient RAM (< ${CRITICAL_RAM}MB)${NC}"
    echo -e "${RED}⚠ SimpleLogin may not function correctly${NC}"
    echo -e "${RED}⚠ Minimum 512MB RAM recommended${NC}"
    echo ""
  elif [ "$total_ram" -lt "$LOW_RAM" ]; then
    echo -e "${YELLOW}━━━ RESOURCE ADVISORY ━━━${NC}"
    echo ""
    echo -e "${YELLOW}⚡ Running in degraded mode due to low RAM${NC}"
    echo -e "${YELLOW}⚡ Some features may be slower${NC}"
    echo -e "${YELLOW}⚡ Consider upgrading to 1GB+ RAM for better performance${NC}"
    echo ""
  fi
  
  # Override Information
  echo -e "${CYAN}━━━ MANUAL OVERRIDES ━━━${NC}"
  echo ""
  echo "To manually override any setting, add to your .env file:"
  echo ""
  echo "  SL_GUNICORN_WORKERS=$gunicorn_workers      # Number of web workers"
  echo "  SL_GUNICORN_TIMEOUT=$gunicorn_timeout       # Request timeout (seconds)"
  echo "  SL_MAX_REQUESTS=$max_requests        # Max requests before worker restart"
  echo "  SL_DB_POOL_SIZE=$db_pool_size          # Database connection pool size"
  echo "  LOW_MEMORY_MODE=false       # Force low-memory mode"
  echo ""
  echo "════════════════════════════════════════════════════════════════"
  echo ""
}

# Run detection and configuration
detect_and_configure

