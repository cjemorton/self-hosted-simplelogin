#!/usr/bin/env bash
#
# instrument-worker-lifecycle.sh - Instrument and trace Gunicorn worker lifecycle
#
# This script adds comprehensive logging and tracing to the Gunicorn worker
# lifecycle to understand exactly what happens during:
# - Worker spawn
# - Worker initialization
# - Request handling
# - Worker timeout
# - Worker restart
# - Out-of-memory conditions
#
# Usage: ./instrument-worker-lifecycle.sh [start|stop|status|tail]
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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
INSTRUMENTATION_DIR="${PROJECT_DIR}/instrumentation-logs"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
LOG_FILE="${INSTRUMENTATION_DIR}/worker-lifecycle-${TIMESTAMP}.log"

log_info() {
  echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
  echo -e "${GREEN}[SUCCESS]${NC} $*"
}

log_warn() {
  echo -e "${YELLOW}[WARN]${NC} $*"
}

log_error() {
  echo -e "${RED}[ERROR]${NC} $*"
}

# Initialize instrumentation directory
init_instrumentation() {
  mkdir -p "$INSTRUMENTATION_DIR"
  
  log_info "Initializing worker lifecycle instrumentation"
  log_info "Log directory: $INSTRUMENTATION_DIR"
  log_info "Current log: $LOG_FILE"
  
  # Create header
  cat <<EOF > "$LOG_FILE"
# Gunicorn Worker Lifecycle Instrumentation Log
# Started: $(date)
# System: $(uname -a)
# Docker: $(docker --version 2>/dev/null || echo "Not available")

EOF
}

# Extract system resource info
log_system_resources() {
  cat <<EOF >> "$LOG_FILE"
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
SYSTEM RESOURCES AT START
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

$(date)

Memory Information:
$(free -h 2>/dev/null || echo "free command not available")

CPU Information:
Cores: $(nproc 2>/dev/null || echo "N/A")
$(cat /proc/cpuinfo 2>/dev/null | grep "model name" | head -1 || echo "CPU info not available")

Container Resources (if applicable):
$(cat /sys/fs/cgroup/memory/memory.limit_in_bytes 2>/dev/null | awk '{printf "Memory Limit: %.2f MB\n", $1/1024/1024}' || echo "Not in cgroup")

EOF
}

# Monitor worker lifecycle events
monitor_worker_lifecycle() {
  log_info "Starting worker lifecycle monitoring"
  
  # Monitor docker logs for worker events
  if docker ps | grep -q sl-app; then
    log_success "Found sl-app container, monitoring..."
    
    cat <<EOF >> "$LOG_FILE"
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
WORKER LIFECYCLE EVENTS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

$(date) - Monitoring started

EOF
    
    # Follow logs and parse worker events
    docker logs -f --since 1m sl-app 2>&1 | while IFS= read -r line; do
      timestamp=$(date +"%Y-%m-%d %H:%M:%S")
      
      # Detect worker events
      if echo "$line" | grep -qi "booting worker"; then
        echo "[$timestamp] 🚀 WORKER_SPAWN: $line" | tee -a "$LOG_FILE"
      elif echo "$line" | grep -qi "worker timeout"; then
        echo "[$timestamp] ⏱️  WORKER_TIMEOUT: $line" | tee -a "$LOG_FILE"
      elif echo "$line" | grep -qi "worker.*exited"; then
        echo "[$timestamp] 💀 WORKER_EXIT: $line" | tee -a "$LOG_FILE"
      elif echo "$line" | grep -qi "out of memory\|oom"; then
        echo "[$timestamp] 💥 OOM_DETECTED: $line" | tee -a "$LOG_FILE"
      elif echo "$line" | grep -qi "listening at"; then
        echo "[$timestamp] 👂 READY: $line" | tee -a "$LOG_FILE"
      elif echo "$line" | grep -qi "restarting worker"; then
        echo "[$timestamp] 🔄 WORKER_RESTART: $line" | tee -a "$LOG_FILE"
      elif echo "$line" | grep -qi "error\|exception"; then
        echo "[$timestamp] ❌ ERROR: $line" | tee -a "$LOG_FILE"
      elif echo "$line" | grep -qi "resource"; then
        echo "[$timestamp] 📊 RESOURCE: $line" | tee -a "$LOG_FILE"
      else
        # Log everything else with timestamp
        echo "[$timestamp] $line" >> "$LOG_FILE"
      fi
    done &
    
    MONITOR_PID=$!
    echo "$MONITOR_PID" > "${INSTRUMENTATION_DIR}/monitor.pid"
    
    log_success "Monitoring worker lifecycle (PID: $MONITOR_PID)"
    log_info "View live: tail -f $LOG_FILE"
    log_info "Stop monitoring: ./instrument-worker-lifecycle.sh stop"
    
  else
    log_error "sl-app container not found. Start it first with 'docker compose up -d app'"
    return 1
  fi
}

# Analyze worker lifecycle from logs
analyze_worker_lifecycle() {
  local log_to_analyze="${1:-$LOG_FILE}"
  
  log_info "Analyzing worker lifecycle from: $log_to_analyze"
  
  if [ ! -f "$log_to_analyze" ]; then
    log_error "Log file not found: $log_to_analyze"
    return 1
  fi
  
  local analysis_file="${log_to_analyze%.log}-ANALYSIS.txt"
  
  cat <<EOF > "$analysis_file"
# Worker Lifecycle Analysis
# Generated: $(date)
# Source: $log_to_analyze

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
WORKER EVENT SUMMARY
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

EOF

  # Count events
  local spawn_count=$(grep -c "WORKER_SPAWN" "$log_to_analyze" 2>/dev/null || echo 0)
  local timeout_count=$(grep -c "WORKER_TIMEOUT" "$log_to_analyze" 2>/dev/null || echo 0)
  local exit_count=$(grep -c "WORKER_EXIT" "$log_to_analyze" 2>/dev/null || echo 0)
  local oom_count=$(grep -c "OOM_DETECTED" "$log_to_analyze" 2>/dev/null || echo 0)
  local restart_count=$(grep -c "WORKER_RESTART" "$log_to_analyze" 2>/dev/null || echo 0)
  local error_count=$(grep -c "ERROR" "$log_to_analyze" 2>/dev/null || echo 0)
  
  cat <<EOF >> "$analysis_file"
Total Worker Spawns:    $spawn_count
Total Worker Timeouts:  $timeout_count
Total Worker Exits:     $exit_count
Total OOM Events:       $oom_count
Total Worker Restarts:  $restart_count
Total Errors:           $error_count

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
TIMELINE OF CRITICAL EVENTS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Worker Spawns:
$(grep "WORKER_SPAWN" "$log_to_analyze" 2>/dev/null || echo "None detected")

Worker Timeouts:
$(grep "WORKER_TIMEOUT" "$log_to_analyze" 2>/dev/null || echo "None detected")

Worker Exits:
$(grep "WORKER_EXIT" "$log_to_analyze" 2>/dev/null || echo "None detected")

OOM Events:
$(grep "OOM_DETECTED" "$log_to_analyze" 2>/dev/null || echo "None detected")

Worker Restarts:
$(grep "WORKER_RESTART" "$log_to_analyze" 2>/dev/null || echo "None detected")

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
HEALTH ASSESSMENT
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

EOF

  # Assess health
  if [ "$timeout_count" -eq 0 ] && [ "$oom_count" -eq 0 ]; then
    echo "Status: ✅ HEALTHY" >> "$analysis_file"
    echo "No worker timeouts or OOM events detected." >> "$analysis_file"
  elif [ "$timeout_count" -gt 0 ] && [ "$oom_count" -eq 0 ]; then
    echo "Status: ⚠️ WORKER TIMEOUTS DETECTED" >> "$analysis_file"
    echo "Worker timeouts occurred but no OOM events." >> "$analysis_file"
    echo "Recommendation: Increase timeout or reduce worker count." >> "$analysis_file"
  elif [ "$oom_count" -gt 0 ]; then
    echo "Status: ❌ OUT OF MEMORY" >> "$analysis_file"
    echo "System ran out of memory. Critical resource shortage." >> "$analysis_file"
    echo "Recommendation: Increase RAM or enable LOW_MEMORY_MODE." >> "$analysis_file"
  else
    echo "Status: ℹ️ INSUFFICIENT DATA" >> "$analysis_file"
    echo "Not enough data to assess health." >> "$analysis_file"
  fi
  
  cat <<EOF >> "$analysis_file"

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
RECOMMENDATIONS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

EOF

  if [ "$timeout_count" -gt 0 ]; then
    cat <<EOF >> "$analysis_file"
Worker Timeout Issues:
  • Current timeouts indicate workers cannot complete initialization
  • Add to .env: SL_GUNICORN_TIMEOUT_OVERRIDE=120
  • Reduce workers: SL_GUNICORN_WORKERS_OVERRIDE=1
  • Check system resources: free -h && docker stats

EOF
  fi
  
  if [ "$oom_count" -gt 0 ]; then
    cat <<EOF >> "$analysis_file"
Out of Memory Issues:
  • System has insufficient RAM for current configuration
  • Enable low-memory mode: LOW_MEMORY_MODE=true
  • Reduce memory limits: SL_APP_MEMORY_LIMIT=256M
  • Add swap space: sudo fallocate -l 1G /swapfile
  • Consider upgrading VPS to 1GB+ RAM

EOF
  fi
  
  if [ "$spawn_count" -gt 10 ]; then
    cat <<EOF >> "$analysis_file"
Excessive Worker Restarts:
  • Workers are restarting frequently ($spawn_count times)
  • This indicates instability
  • Check error logs for root cause
  • May indicate memory leaks or application bugs

EOF
  fi
  
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >> "$analysis_file"
  
  log_success "Analysis complete: $analysis_file"
  cat "$analysis_file"
}

# Stop monitoring
stop_monitoring() {
  if [ -f "${INSTRUMENTATION_DIR}/monitor.pid" ]; then
    local pid=$(cat "${INSTRUMENTATION_DIR}/monitor.pid")
    if ps -p "$pid" > /dev/null 2>&1; then
      log_info "Stopping monitoring (PID: $pid)"
      kill "$pid" 2>/dev/null || true
      rm -f "${INSTRUMENTATION_DIR}/monitor.pid"
      log_success "Monitoring stopped"
      
      # Analyze the logs we collected
      log_info "Analyzing collected data..."
      analyze_worker_lifecycle
    else
      log_warn "Monitor process not running"
      rm -f "${INSTRUMENTATION_DIR}/monitor.pid"
    fi
  else
    log_warn "No active monitoring session found"
  fi
}

# Show status
show_status() {
  if [ -f "${INSTRUMENTATION_DIR}/monitor.pid" ]; then
    local pid=$(cat "${INSTRUMENTATION_DIR}/monitor.pid")
    if ps -p "$pid" > /dev/null 2>&1; then
      log_success "Monitoring is ACTIVE (PID: $pid)"
      log_info "Log file: $LOG_FILE"
      log_info "View live: tail -f $LOG_FILE"
    else
      log_warn "Monitor PID file exists but process is not running"
      rm -f "${INSTRUMENTATION_DIR}/monitor.pid"
    fi
  else
    log_info "No active monitoring session"
  fi
  
  # Show recent logs
  if [ -f "$LOG_FILE" ]; then
    log_info "Recent events:"
    echo ""
    tail -20 "$LOG_FILE" | grep -E "WORKER_|OOM_|ERROR|RESOURCE" || echo "No recent events"
  fi
}

# Tail logs
tail_logs() {
  if [ -f "$LOG_FILE" ]; then
    log_info "Tailing: $LOG_FILE"
    tail -f "$LOG_FILE"
  else
    log_error "No log file found: $LOG_FILE"
    log_info "Start monitoring first: ./instrument-worker-lifecycle.sh start"
  fi
}

# Main execution
main() {
  local command="${1:-start}"
  
  case "$command" in
    start)
      init_instrumentation
      log_system_resources
      monitor_worker_lifecycle
      ;;
    stop)
      stop_monitoring
      ;;
    status)
      show_status
      ;;
    tail)
      tail_logs
      ;;
    analyze)
      if [ -n "${2:-}" ]; then
        analyze_worker_lifecycle "$2"
      else
        analyze_worker_lifecycle
      fi
      ;;
    *)
      echo "Usage: $0 [start|stop|status|tail|analyze]"
      echo ""
      echo "Commands:"
      echo "  start    - Start monitoring worker lifecycle"
      echo "  stop     - Stop monitoring and analyze results"
      echo "  status   - Show current monitoring status"
      echo "  tail     - Follow live instrumentation logs"
      echo "  analyze  - Analyze worker lifecycle from logs"
      exit 1
      ;;
  esac
}

main "$@"
