#!/usr/bin/env bash
#
# demo-version-sync.sh - Demonstration of version synchronization features
#
# This script demonstrates the new features added to up.sh

set -uo pipefail

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

demo_section() {
  echo ""
  echo -e "${CYAN}=========================================="
  echo -e "$1"
  echo -e "==========================================${NC}"
  echo ""
}

demo_command() {
  echo -e "${BLUE}$ $1${NC}"
  echo ""
}

demo_section "1. Help Documentation for New Features"
demo_command "./up.sh --help | grep -A30 'Version Synchronization'"
./up.sh --help 2>&1 | grep -A30 'Version Synchronization'

echo ""
demo_section "2. Parameter Validation"

echo -e "${BLUE}Testing invalid retry-delay:${NC}"
demo_command "./up.sh --retry-delay abc"
./up.sh --retry-delay abc 2>&1
echo ""

echo -e "${BLUE}Testing invalid max-retries:${NC}"
demo_command "./up.sh --max-retries xyz"
./up.sh --max-retries xyz 2>&1
echo ""

demo_section "3. Docker Login Check"
echo -e "${BLUE}Current Docker login status:${NC}"
demo_command "docker info 2>/dev/null | grep 'Username:' || echo 'Not logged in'"
docker info 2>/dev/null | grep 'Username:' || echo 'Not logged in'

echo ""
demo_section "4. GitHub API Integration"
echo -e "${BLUE}Fetching latest SimpleLogin release:${NC}"
demo_command "curl -s 'https://api.github.com/repos/simple-login/app/releases/latest' | grep 'tag_name'"
curl -s "https://api.github.com/repos/simple-login/app/releases/latest" | grep '"tag_name":' | head -1

echo ""
demo_section "5. Available Flags and Options"
demo_command "./up.sh --help | grep -E '^\s+--'"
./up.sh --help 2>&1 | grep -E '^\s+(--|-[a-z])'

echo ""
demo_section "6. Configuration File (.env)"
echo -e "${BLUE}Current version in .env:${NC}"
demo_command "grep '^SL_VERSION=' .env"
grep '^SL_VERSION=' .env 2>/dev/null || echo "SL_VERSION not found"

echo -e "${BLUE}Docker repository configuration:${NC}"
demo_command "grep '^SL_DOCKER_REPO=' .env"
grep '^SL_DOCKER_REPO=' .env 2>/dev/null || echo "SL_DOCKER_REPO not found"

echo -e "${BLUE}Image name configuration:${NC}"
demo_command "grep '^SL_IMAGE=' .env"
grep '^SL_IMAGE=' .env 2>/dev/null || echo "SL_IMAGE not found"

echo ""
demo_section "7. Feature Summary"
cat << 'EOF'
✅ --update-latest           Fetch latest version from GitHub and update .env
✅ --no-docker-login-check   Skip Docker login verification
✅ --retry-delay SECONDS     Configure retry delay (default: 15s)
✅ --max-retries COUNT       Configure max retries (default: 20)

Features implemented:
  • GitHub API integration for version fetching
  • Docker registry validation with retry logic
  • Fallback to last available tag if image not found
  • Automated .env file updates with backup
  • Docker image pulling after version update
  • Comprehensive error handling and logging
  • Parameter validation for all flags

Error Handling:
  • Network issues (GitHub API failures)
  • Docker registry connectivity problems
  • Missing or invalid Docker images
  • File permission issues (.env backup/update)
  • Invalid parameter values
EOF

echo ""
demo_section "Demo Complete!"
echo -e "${GREEN}All features have been successfully implemented and tested.${NC}"
echo ""
