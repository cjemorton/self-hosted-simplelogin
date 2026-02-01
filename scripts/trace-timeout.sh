#!/usr/bin/env bash
#
# trace-timeout.sh - Diagnostic script to trace timeout value propagation
#
# This script helps diagnose why DB_WAIT_TIMEOUT may not be working correctly
# by tracing the value through all layers of execution.
#

set -euo pipefail

echo "========================================="
echo "Timeout Value Tracing Diagnostic"
echo "========================================="
echo ""

echo "Environment Context:"
echo "-------------------"
echo "Current user: $(whoami)"
echo "Current directory: $(pwd)"
echo "Shell: $SHELL"
echo "BASH_VERSION: $BASH_VERSION"
echo ""

echo "Environment Variables:"
echo "---------------------"
echo "DB_WAIT_TIMEOUT=${DB_WAIT_TIMEOUT:-<NOT SET>}"
echo "POSTGRES_HOST=${POSTGRES_HOST:-<NOT SET>}"
echo "POSTGRES_PORT=${POSTGRES_PORT:-<NOT SET>}"
echo "POSTGRES_DB=${POSTGRES_DB:-<NOT SET>}"
echo "POSTGRES_USER=${POSTGRES_USER:-<NOT SET>}"
echo "DB_URI=${DB_URI:-<NOT SET>}"
echo ""

echo "Script Arguments:"
echo "----------------"
echo "Number of arguments: $#"
if [ $# -gt 0 ]; then
  for i in $(seq 1 $#); do
    echo "Arg $i: ${!i}"
  done
else
  echo "(no arguments)"
fi
echo ""

echo "Timeout Value Resolution:"
echo "------------------------"
timeout="${DB_WAIT_TIMEOUT:-60}"
echo "Variable assignment: timeout=\"\${DB_WAIT_TIMEOUT:-60}\""
echo "Resolved value: $timeout"
echo ""

echo "Script Locations:"
echo "----------------"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo "SCRIPT_DIR=$SCRIPT_DIR"
echo "run-migration.sh: $(ls -la "$SCRIPT_DIR/run-migration.sh" 2>&1 || echo 'NOT FOUND')"
echo "wait-for-db.sh: $(ls -la "$SCRIPT_DIR/wait-for-db.sh" 2>&1 || echo 'NOT FOUND')"
echo ""

echo "Testing Child Script Invocation:"
echo "--------------------------------"
if [ -f "$SCRIPT_DIR/wait-for-db.sh" ]; then
  echo "Simulating: bash $SCRIPT_DIR/wait-for-db.sh $timeout"
  echo "(This will show what wait-for-db.sh receives)"
  echo ""
  
  # Create a wrapper to trace what wait-for-db.sh receives
  cat > /tmp/trace-wrapper.sh << 'WRAPPER_EOF'
#!/bin/bash
echo "=== wait-for-db.sh simulation ==="
echo "Received arguments: $#"
echo "Arg 1: ${1:-<NOT PROVIDED>}"
TIMEOUT="${1:-60}"
echo "TIMEOUT variable set to: $TIMEOUT"
echo "=================================="
WRAPPER_EOF
  chmod +x /tmp/trace-wrapper.sh
  
  bash /tmp/trace-wrapper.sh "$timeout"
else
  echo "wait-for-db.sh not found, cannot simulate"
fi
echo ""

echo "Docker Environment Check:"
echo "------------------------"
if [ -f /.dockerenv ]; then
  echo "Running inside Docker container: YES"
  echo "Container hostname: $(hostname)"
else
  echo "Running inside Docker container: NO"
fi
echo ""

echo "========================================="
echo "Diagnostic Complete"
echo "========================================="
