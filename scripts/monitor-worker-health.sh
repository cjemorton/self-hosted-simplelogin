#!/usr/bin/env bash
#
# monitor-worker-health.sh - Real-time worker health monitoring
#
# This script provides continuous monitoring of Gunicorn worker health,
# detecting and alerting on:
# - Worker timeouts
# - Out of memory conditions
# - Worker restarts
# - Memory pressure
# - CPU utilization
# - Request processing times
#
# Usage: ./monitor-worker-health.sh [--interval SECONDS] [--alert-on-timeout]
#

set -euo pipefail

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# Configuration
INTERVAL="${1:-5}"  # Check interval in seconds
ALERT_ON_TIMEOUT="${2:-false}"
CONTAINER_NAME="sl-app"

log_info() {
  echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
  echo -e "${GREEN}[✓]${NC} $*"
}

log_warn() {
  echo -e "${YELLOW}[⚠]${NC} $*"
}

log_error() {
  echo -e "${RED}[✗]${NC} $*"
}

# Check if container is running
check_container() {
  if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    log_error "Container $CONTAINER_NAME is not running"
    return 1
  fi
  return 0
}

# Get container stats
get_container_stats() {
  docker stats "$CONTAINER_NAME" --no-stream --format "{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}" 2>/dev/null
}

# Parse memory usage
parse_memory() {
  local mem_usage="$1"
  # Extract just the used memory (e.g., "123.4MiB / 512MiB" -> "123.4")
  echo "$mem_usage" | awk '{print $1}' | sed 's/[^0-9.]//g'
}

# Get worker count from logs
get_worker_count() {
  docker logs "$CONTAINER_NAME" 2>&1 | grep -oP "Workers:\s+\K\d+" | tail -1 || echo "?"
}

# Get timeout setting from logs
get_timeout_setting() {
  docker logs "$CONTAINER_NAME" 2>&1 | grep -oP "Timeout:\s+\K\d+" | tail -1 || echo "?"
}

# Check for recent worker events
check_worker_events() {
  local since_time="${1:-1m}"
  
  # Get recent logs
  local recent_logs
  recent_logs=$(docker logs "$CONTAINER_NAME" --since "$since_time" 2>&1)
  
  # Count events
  local timeouts=$(echo "$recent_logs" | grep -ic "worker timeout" || echo 0)
  local restarts=$(echo "$recent_logs" | grep -ic "restarting worker\|worker.*exited" || echo 0)
  local ooms=$(echo "$recent_logs" | grep -ic "out of memory\|oom" || echo 0)
  local errors=$(echo "$recent_logs" | grep -ic "error\|exception" || echo 0)
  
  echo "$timeouts:$restarts:$ooms:$errors"
}

# Display dashboard
display_dashboard() {
  local iteration=$1
  
  # Clear screen
  clear
  
  # Header
  echo "╔════════════════════════════════════════════════════════════════╗"
  echo "║         SimpleLogin Worker Health Monitoring Dashboard         ║"
  echo "╚════════════════════════════════════════════════════════════════╝"
  echo ""
  echo "$(date '+%Y-%m-%d %H:%M:%S')  |  Iteration: $iteration  |  Interval: ${INTERVAL}s"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
  
  # Check container status
  if ! check_container; then
    echo -e "${RED}Container $CONTAINER_NAME is not running!${NC}"
    echo ""
    echo "Start the container with: docker compose up -d app"
    return 1
  fi
  
  # Get stats
  local stats
  stats=$(get_container_stats)
  local cpu=$(echo "$stats" | cut -f1)
  local mem_usage=$(echo "$stats" | cut -f2)
  local mem_percent=$(echo "$stats" | cut -f3)
  
  # Get configuration
  local workers=$(get_worker_count)
  local timeout=$(get_timeout_setting)
  
  # Get recent events
  local events
  events=$(check_worker_events "1m")
  local timeouts=$(echo "$events" | cut -d: -f1)
  local restarts=$(echo "$events" | cut -d: -f2)
  local ooms=$(echo "$events" | cut -d: -f3)
  local errors=$(echo "$events" | cut -d: -f4)
  
  # System Resources
  echo -e "${CYAN}━━━ CONTAINER RESOURCES ━━━${NC}"
  echo ""
  printf "  CPU Usage:      %-20s" "$cpu"
  if [ "${cpu%\%}" -gt 80 ] 2>/dev/null; then
    echo -e "${RED}[HIGH]${NC}"
  elif [ "${cpu%\%}" -gt 50 ] 2>/dev/null; then
    echo -e "${YELLOW}[MODERATE]${NC}"
  else
    echo -e "${GREEN}[NORMAL]${NC}"
  fi
  
  printf "  Memory Usage:   %-20s" "$mem_usage"
  if [ "${mem_percent%\%}" -gt 90 ] 2>/dev/null; then
    echo -e "${RED}[CRITICAL]${NC}"
  elif [ "${mem_percent%\%}" -gt 75 ] 2>/dev/null; then
    echo -e "${YELLOW}[HIGH]${NC}"
  else
    echo -e "${GREEN}[NORMAL]${NC}"
  fi
  
  echo ""
  
  # Worker Configuration
  echo -e "${CYAN}━━━ WORKER CONFIGURATION ━━━${NC}"
  echo ""
  echo "  Workers:        $workers"
  echo "  Timeout:        ${timeout}s"
  echo ""
  
  # Worker Health - Last Minute
  echo -e "${CYAN}━━━ WORKER HEALTH (Last 60s) ━━━${NC}"
  echo ""
  
  # Timeouts
  printf "  Worker Timeouts:   %2d  " "$timeouts"
  if [ "$timeouts" -gt 0 ]; then
    echo -e "${RED}[ALERT]${NC}"
  else
    echo -e "${GREEN}[OK]${NC}"
  fi
  
  # Restarts
  printf "  Worker Restarts:   %2d  " "$restarts"
  if [ "$restarts" -gt 5 ]; then
    echo -e "${RED}[HIGH]${NC}"
  elif [ "$restarts" -gt 0 ]; then
    echo -e "${YELLOW}[SOME]${NC}"
  else
    echo -e "${GREEN}[NONE]${NC}"
  fi
  
  # OOM
  printf "  OOM Events:        %2d  " "$ooms"
  if [ "$ooms" -gt 0 ]; then
    echo -e "${RED}[CRITICAL]${NC}"
  else
    echo -e "${GREEN}[NONE]${NC}"
  fi
  
  # Errors
  printf "  Errors:            %2d  " "$errors"
  if [ "$errors" -gt 10 ]; then
    echo -e "${RED}[HIGH]${NC}"
  elif [ "$errors" -gt 0 ]; then
    echo -e "${YELLOW}[SOME]${NC}"
  else
    echo -e "${GREEN}[NONE]${NC}"
  fi
  
  echo ""
  
  # Overall Health Assessment
  echo -e "${CYAN}━━━ HEALTH ASSESSMENT ━━━${NC}"
  echo ""
  
  if [ "$timeouts" -eq 0 ] && [ "$ooms" -eq 0 ] && [ "$restarts" -lt 3 ]; then
    echo -e "  Status: ${GREEN}✓ HEALTHY${NC}"
    echo "  Workers are operating normally"
  elif [ "$timeouts" -gt 0 ] && [ "$ooms" -eq 0 ]; then
    echo -e "  Status: ${YELLOW}⚠ TIMEOUTS DETECTED${NC}"
    echo "  Workers are timing out - consider:"
    echo "    • Increasing timeout: SL_GUNICORN_TIMEOUT_OVERRIDE=120"
    echo "    • Reducing workers: SL_GUNICORN_WORKERS_OVERRIDE=1"
  elif [ "$ooms" -gt 0 ]; then
    echo -e "  Status: ${RED}✗ OUT OF MEMORY${NC}"
    echo "  System is running out of memory - CRITICAL:"
    echo "    • Enable LOW_MEMORY_MODE=true"
    echo "    • Reduce memory limits or increase system RAM"
    echo "    • Add swap space"
  elif [ "$restarts" -gt 5 ]; then
    echo -e "  Status: ${YELLOW}⚠ FREQUENT RESTARTS${NC}"
    echo "  Workers restarting frequently:"
    echo "    • Check application logs for errors"
    echo "    • May indicate memory leaks"
  else
    echo -e "  Status: ${GREEN}✓ GENERALLY HEALTHY${NC}"
    echo "  Minor issues detected but system operational"
  fi
  
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
  echo "Press Ctrl+C to exit"
  
  # Alert if timeouts detected
  if [ "$ALERT_ON_TIMEOUT" = "true" ] && [ "$timeouts" -gt 0 ]; then
    echo ""
    log_error "ALERT: Worker timeouts detected! Check configuration."
  fi
}

# Main monitoring loop
main() {
  log_info "Starting worker health monitoring"
  log_info "Container: $CONTAINER_NAME"
  log_info "Check interval: ${INTERVAL}s"
  echo ""
  
  local iteration=0
  
  while true; do
    iteration=$((iteration + 1))
    display_dashboard "$iteration"
    sleep "$INTERVAL"
  done
}

# Handle Ctrl+C gracefully
trap 'echo ""; log_info "Monitoring stopped"; exit 0' INT TERM

# Run main
main
