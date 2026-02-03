#!/usr/bin/env bash

## use `--remove-orphans` to remove nginx container from previous versions, to free up ports 80/443 for traefik
##
## Usage:
##   ./up.sh              - Start containers in detached mode (background, default)
##   ./up.sh -f           - Start containers in foreground mode (shows logs on screen)
##   ./up.sh -c           - Cleanup dangling/unused Docker images and volumes before starting
##   ./up.sh -r           - Fresh install: wipe all data and start from scratch (requires confirmation)
##   ./up.sh TAG_VERSION  - Use specified tag version (e.g., ./up.sh v1.0.0)
##
## Options:
##   -f, --foreground            Run docker compose in foreground mode (no -d flag)
##   -c, --cleanup               Cleanup dangling/unused Docker images and volumes
##       --deep-cleanup          Perform deep cleanup (system prune with volumes) - USE WITH CAUTION
##   -r, --fresh                 Fresh install: stop containers, remove volumes, start fresh
##   -y, --yes                   Skip confirmation prompts (for automation)
##       --update-latest         Fetch latest tag from GitHub and update .env
##       --update-tag TAG        Update to specific tag version and update .env
##       --no-docker-login-check Skip Docker login verification
##       --retry-delay SECONDS   Delay between retries (default: 15s)
##       --max-retries COUNT     Maximum retry attempts (default: 20)
##   -h, --help                  Show this help message
##
## Docker Image Validation:
##   This script uses SL_VERSION from .env as the single source of truth for Docker versioning.
##   Before starting:
##     1. Checks if the image exists locally (no remote calls if found)
##     2. If not local, checks the remote Docker registry (Docker Hub)
##     3. If not found anywhere, prints a clear error with instructions
##
## Version Synchronization (--update-latest or --update-tag):
##   Automatically fetches tags from GitHub and updates your .env:
##     1. Queries GitHub API for tags (latest tag or specified tag)
##     2. Validates the tag's Docker image exists in configured registry
##     3. Retries with configurable delay if image not yet available
##     4. Falls back to last available tag if retries exhausted (for --update-latest only)
##     5. Updates SL_VERSION in .env when successful
##     6. Pulls the Docker image
##
##   Environment Variables:
##     - SL_DOCKER_REPO: Docker repository to check (default: clem16)
##     - SL_IMAGE: Docker image name (default: simplelogin-app)
##     - SL_GITHUB_REPO_USER: GitHub user/org for version tags (default: simple-login)
##     - SL_GITHUB_REPO_PROJECT: GitHub project for version tags (default: app)
##
##   TODO: Consider automating the build/push process from upstream SimpleLogin images
##         to simplify version management and reduce manual intervention.

# Parse command line options
FOREGROUND_MODE=false
CLEANUP_MODE=false
DEEP_CLEANUP=false
FRESH_INSTALL=false
AUTO_YES=false
UPDATE_LATEST=false
UPDATE_TAG=""
NO_DOCKER_LOGIN_CHECK=false
RETRY_DELAY=15
MAX_RETRIES=20

show_usage() {
  echo "Usage: ./up.sh [OPTIONS]"
  echo ""
  echo "Start SimpleLogin containers using docker compose"
  echo ""
  echo "Options:"
  echo "  -f, --foreground            Run docker compose in foreground mode (shows logs on screen)"
  echo "  -c, --cleanup               Cleanup dangling/unused Docker images and volumes before starting"
  echo "      --deep-cleanup          Perform deep cleanup (system prune with volumes) - USE WITH CAUTION"
  echo "  -r, --fresh                 Fresh install: stop containers, remove volumes, start fresh"
  echo "  -y, --yes                   Skip confirmation prompts (for automation)"
  echo "      --update-latest         Fetch latest tag from GitHub and update .env"
  echo "      --update-tag TAG        Update to specific tag version and update .env"
  echo "      --no-docker-login-check Skip Docker login verification before operations"
  echo "      --retry-delay SECONDS   Delay between retries when checking for Docker images (default: 15s)"
  echo "      --max-retries COUNT     Maximum retry attempts for Docker image availability (default: 20)"
  echo "  -h, --help                  Show this help message"
  echo ""
  echo "Docker Image Validation:"
  echo "  This script uses SL_VERSION from .env as the single source of truth."
  echo "  It checks for image existence (local first, then remote) before starting."
  echo ""
  echo "Version Synchronization (--update-latest, --update-tag):"
  echo "  Automatically updates to a SimpleLogin tag:"
  echo "    1. Fetches tag from GitHub API (latest or specified)"
  echo "    2. Validates Docker image exists in configured registry"
  echo "    3. Retries with delay if image not yet available (configurable)"
  echo "    4. Falls back to last available tag if max retries exceeded (--update-latest only)"
  echo "    5. Updates SL_VERSION in .env file"
  echo "    6. Pulls the Docker image"
  echo ""
  echo "  Environment Variables:"
  echo "    - SL_DOCKER_REPO: Docker repository to check (default: clem16)"
  echo "    - SL_IMAGE: Docker image name (default: simplelogin-app)"
  echo "    - SL_GITHUB_REPO_USER: GitHub user/org for version tags (default: simple-login)"
  echo "    - SL_GITHUB_REPO_PROJECT: GitHub project for version tags (default: app)"
  echo ""
  echo "  Retry Behavior:"
  echo "    Use --retry-delay and --max-retries to customize waiting for new images."
  echo "    Default: 20 retries × 15s = 5 minutes maximum wait time."
  echo ""
  echo "Docker Login Check:"
  echo "  By default, the script verifies Docker login status before operations."
  echo "  Use --no-docker-login-check to skip this verification (not recommended)."
  echo ""
  echo "Examples:"
  echo "  ./up.sh                     # Start in detached mode (background)"
  echo "  ./up.sh -f                  # Start in foreground mode"
  echo "  ./up.sh -c                  # Cleanup unused Docker resources, then start"
  echo "  ./up.sh --deep-cleanup      # Deep cleanup (removes ALL unused Docker data)"
  echo "  ./up.sh -r                  # Fresh install (prompts for confirmation)"
  echo "  ./up.sh -r -y               # Fresh install (no confirmation, for automation)"
  echo "  ./up.sh --update-latest     # Update to latest tag from GitHub"
  echo "  ./up.sh --update-tag v1.0.0 # Update to specific tag v1.0.0"
  echo "  ./up.sh --update-latest --retry-delay 30 --max-retries 10"
  echo "                              # Update with custom retry settings"
  echo ""
  echo "⚠️  WARNING - Fresh Install (-r, --fresh):"
  echo "    This will PERMANENTLY DELETE all data including:"
  echo "    - All database data"
  echo "    - Uploaded files"
  echo "    - PGP keys"
  echo "    - DKIM keys"
  echo "    - Traefik certificates"
  echo "    Use with caution! There is no undo."
  echo ""
  echo "⚠️  WARNING - Deep Cleanup (--deep-cleanup):"
  echo "    This will remove ALL unused Docker resources system-wide, not just"
  echo "    this project's resources. Use regular -c for safer cleanup."
  exit 0
}

while getopts "fcryh-:" opt; do
  case $opt in
    f)
      FOREGROUND_MODE=true
      ;;
    c)
      CLEANUP_MODE=true
      ;;
    r)
      FRESH_INSTALL=true
      ;;
    y)
      AUTO_YES=true
      ;;
    h)
      show_usage
      ;;
    -)
      # Handle long options
      case "${OPTARG}" in
        foreground)
          FOREGROUND_MODE=true
          ;;
        cleanup)
          CLEANUP_MODE=true
          ;;
        deep-cleanup)
          CLEANUP_MODE=true
          DEEP_CLEANUP=true
          ;;
        fresh)
          FRESH_INSTALL=true
          ;;
        yes)
          AUTO_YES=true
          ;;
        update-latest)
          UPDATE_LATEST=true
          ;;
        update-tag)
          UPDATE_TAG="${!OPTIND}"
          OPTIND=$((OPTIND + 1))
          # Validate update-tag has a value
          if [ -z "$UPDATE_TAG" ]; then
            echo "ERROR: --update-tag requires a tag value" >&2
            exit 1
          fi
          ;;
        no-docker-login-check)
          NO_DOCKER_LOGIN_CHECK=true
          ;;
        retry-delay)
          RETRY_DELAY="${!OPTIND}"
          OPTIND=$((OPTIND + 1))
          # Validate retry-delay is a number
          if ! [[ "$RETRY_DELAY" =~ ^[0-9]+$ ]]; then
            echo "ERROR: --retry-delay must be a positive number" >&2
            exit 1
          fi
          ;;
        max-retries)
          MAX_RETRIES="${!OPTIND}"
          OPTIND=$((OPTIND + 1))
          # Validate max-retries is a number
          if ! [[ "$MAX_RETRIES" =~ ^[0-9]+$ ]]; then
            echo "ERROR: --max-retries must be a positive number" >&2
            exit 1
          fi
          ;;
        help)
          show_usage
          ;;
        *)
          echo "Invalid option: --$OPTARG" >&2
          echo "Use -h or --help for help"
          exit 1
          ;;
      esac
      ;;
    \?)
      echo "Invalid option: -$OPTARG" >&2
      echo "Use -h for help"
      exit 1
      ;;
  esac
done

# Shift past the parsed options
shift $((OPTIND-1))

# Logging helper functions
# All log functions output to stderr (>&2) to avoid polluting command substitution
# when used inside functions whose output is captured with $()
log_info() {
  echo "[INFO] $*" >&2
}

log_success() {
  echo "✓ $*" >&2
}

log_error() {
  echo "ERROR: $*" >&2
}

log_warning() {
  echo "⚠️  WARNING: $*" >&2
}

# Function to check Docker login status
check_docker_login() {
  log_info "Checking Docker login status..."
  
  # Check if docker info includes Username field
  if docker info 2>/dev/null | grep -q "Username:"; then
    local username=$(docker info 2>/dev/null | grep "Username:" | awk '{print $2}')
    log_success "Docker is logged in as: $username"
    return 0
  else
    log_error "Docker is not logged in!"
    echo ""
    echo "Please log in to Docker before running this script:"
    echo "  docker login"
    echo ""
    echo "Or use --no-docker-login-check to skip this verification (not recommended)."
    return 1
  fi
}

# Function to fetch latest GitHub tag (or specific tag)
# NOTE: All log_* functions used in this function output to stderr (>&2) to prevent
# log messages from being captured when this function's output is assigned to a variable.
# This is critical to avoid tag pollution bugs where Docker image names become malformed
# like: "clem16/simplelogin-app:[INFO] Fetching latest tag... v1.0.0"
# See: Tag validation and sanitization functions below for additional safeguards.
fetch_latest_github_tag() {
  local github_repo="$1"
  local specific_tag="${2:-}"
  
  if [ -n "$specific_tag" ]; then
    log_info "Verifying tag '$specific_tag' exists on GitHub: $github_repo..."
    
    # Check if specific tag exists
    local api_url="https://api.github.com/repos/${github_repo}/tags"
    local response=$(curl -s -f "$api_url" 2>/dev/null)
    
    if [ $? -ne 0 ] || [ -z "$response" ]; then
      log_error "Failed to fetch tags from GitHub API"
      return 1
    fi
    
    # Check if the specific tag exists in the response
    if echo "$response" | grep -q "\"name\"[[:space:]]*:[[:space:]]*\"${specific_tag}\""; then
      log_success "Tag '$specific_tag' found on GitHub"
      echo "$specific_tag"
      return 0
    else
      log_error "Tag '$specific_tag' not found on GitHub"
      log_info "Available tags can be viewed at: https://github.com/${github_repo}/tags"
      return 1
    fi
  fi
  
  # Fetch latest tag
  log_info "Fetching latest tag from GitHub: $github_repo..."
  
  # Use GitHub API to get tags (primary method)
  local api_url="https://api.github.com/repos/${github_repo}/tags"
  local response=$(curl -s -f "$api_url" 2>/dev/null)
  
  if [ $? -ne 0 ] || [ -z "$response" ]; then
    log_error "Failed to fetch tags from GitHub API"
    log_info "Trying to fetch latest release as fallback..."
    
    # Fallback: try to get latest release
    api_url="https://api.github.com/repos/${github_repo}/releases/latest"
    response=$(curl -s -f "$api_url" 2>/dev/null)
    
    if [ $? -ne 0 ] || [ -z "$response" ]; then
      log_error "Failed to fetch releases from GitHub API"
      return 1
    fi
    
    # Extract tag_name from release - use more precise pattern to avoid greedy matching
    # Pattern: match "tag_name": followed by whitespace and quoted string
    # Note: Using grep/sed for JSON parsing to avoid external dependencies (jq)
    # Expected JSON: {"tag_name": "v1.0.0", ...} or {"tag_name":"v1.0.0",...}
    local tag_name=$(echo "$response" | grep -o '"tag_name"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"\([^"]*\)"$/\1/')
  else
    # Extract first tag name - use more precise pattern to avoid greedy matching
    # Pattern: match "name": followed by whitespace and quoted string
    # Note: Using grep/sed for JSON parsing to avoid external dependencies (jq)
    # Expected JSON: {"name": "v1.0.0", ...} or {"name":"v1.0.0",...}
    local tag_name=$(echo "$response" | grep -o '"name"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"\([^"]*\)"$/\1/')
  fi
  
  if [ -z "$tag_name" ]; then
    log_error "Could not extract tag name from GitHub response"
    return 1
  fi
  
  echo "$tag_name"
  return 0
}

# Function to validate and sanitize a tag value
# Ensures the tag contains only valid characters and is not polluted with log output
# Returns 0 if valid, 1 if invalid
validate_tag() {
  local tag="$1"
  
  # Check if tag is empty
  if [ -z "$tag" ]; then
    log_error "Tag validation failed: tag is empty"
    return 1
  fi
  
  # Check if tag contains newlines (indicates multi-line pollution)
  # Use parameter expansion to check for newlines without echo
  if [ "$tag" != "${tag//$'\n'/}" ]; then
    log_error "Tag validation failed: tag contains newlines"
    log_error "Malformed tag value: '$tag'"
    log_error "This usually indicates log output polluting the tag extraction"
    return 1
  fi
  
  # Check if tag contains spaces (indicates log message pollution)
  if [[ "$tag" =~ [[:space:]] ]]; then
    log_error "Tag validation failed: tag contains spaces"
    log_error "Malformed tag value: '$tag'"
    log_error "This usually indicates log output polluting the tag extraction"
    return 1
  fi
  
  # Check if tag contains suspicious characters that shouldn't be in a version tag
  # Valid characters: alphanumeric, dot, hyphen, underscore
  if ! [[ "$tag" =~ ^[a-zA-Z0-9._-]+$ ]]; then
    log_error "Tag validation failed: tag contains invalid characters"
    log_error "Malformed tag value: '$tag'"
    log_error "Tags should only contain alphanumeric characters, dots, hyphens, and underscores"
    return 1
  fi
  
  # Tag is valid
  return 0
}

# Function to sanitize a tag by extracting only the last word
# This handles cases where log output may have polluted the tag variable
# Example: "[INFO] Fetching... v1.0.0" -> "v1.0.0"
sanitize_tag() {
  local tag="$1"
  
  # Extract the last word (handles space-separated pollution)
  # Use awk to get the last field, which should be the actual tag
  local sanitized=$(echo "$tag" | awk '{print $NF}')
  
  # Remove any trailing/leading whitespace or newlines
  sanitized=$(echo "$sanitized" | tr -d '\n\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
  
  echo "$sanitized"
}

# Function to check if Docker image exists in registry
check_docker_image_exists() {
  local image="$1"
  log_info "Checking if Docker image exists: $image"
  
  # Try docker manifest inspect (works without pulling)
  if docker manifest inspect "$image" &>/dev/null; then
    log_success "Docker image found: $image"
    return 0
  else
    log_warning "Docker image not found: $image"
    return 1
  fi
}

# Function to get all available tags for a Docker image
get_available_docker_tags() {
  local repo="$1"
  local image_name="$2"
  log_info "Fetching available tags from Docker registry..."
  
  # For Docker Hub, use the registry API
  # Note: This relies on Docker Hub API returning JSON with consistent formatting
  # Using grep/sed for JSON parsing to avoid external dependencies (jq)
  # Expected format: {"results": [{"name": "tag1"}, {"name": "tag2"}, ...]}
  local api_url="https://registry.hub.docker.com/v2/repositories/${repo}/${image_name}/tags?page_size=100"
  local response=$(curl -s -f "$api_url" 2>/dev/null)
  
  if [ $? -ne 0 ] || [ -z "$response" ]; then
    log_error "Failed to fetch tags from Docker registry"
    return 1
  fi
  
  # Extract tag names using more precise pattern to avoid greedy matching
  # Pattern: match "name": followed by whitespace and quoted string
  local tags=$(echo "$response" | grep -o '"name"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"\([^"]*\)"$/\1/')
  echo "$tags"
  return 0
}

# Function to update .env file with new version
update_env_version() {
  local new_version="$1"
  log_info "Updating .env with new version: $new_version"
  
  if [ ! -f .env ]; then
    log_error ".env file not found!"
    return 1
  fi
  
  # Check if SL_VERSION exists in .env
  if ! grep -q "^SL_VERSION=" .env; then
    log_error "SL_VERSION not found in .env file"
    return 1
  fi
  
  # Create backup
  cp .env .env.backup
  log_info "Created backup: .env.backup"
  
  # Update SL_VERSION in .env
  if sed -i "s/^SL_VERSION=.*/SL_VERSION=${new_version}/" .env; then
    log_success "Updated SL_VERSION to: $new_version"
    
    # Show the change
    echo "Old version: $(grep '^SL_VERSION=' .env.backup | cut -d'=' -f2)"
    echo "New version: $(grep '^SL_VERSION=' .env | cut -d'=' -f2)"
    return 0
  else
    log_error "Failed to update .env file"
    # Restore backup
    mv .env.backup .env
    return 1
  fi
}

# Function to perform version update from GitHub
perform_version_update() {
  local specified_tag="${1:-}"
  
  echo "=========================================="
  if [ -n "$specified_tag" ]; then
    echo "Version Synchronization - Update to Tag: $specified_tag"
  else
    echo "Version Synchronization - Update Latest"
  fi
  echo "=========================================="
  echo ""
  
  # Load current configuration
  if [ ! -f .env ]; then
    log_error ".env file not found!"
    echo "Please copy .env.example to .env and configure it:"
    echo "  cp .env.example .env"
    exit 1
  fi
  
  # Get current version and Docker repo settings
  local current_version=$(grep "^SL_VERSION=" .env 2>/dev/null | cut -d'=' -f2)
  local docker_repo=$(grep "^SL_DOCKER_REPO=" .env 2>/dev/null | cut -d'=' -f2)
  local image_name=$(grep "^SL_IMAGE=" .env 2>/dev/null | cut -d'=' -f2)
  
  # Use defaults if not set
  docker_repo="${docker_repo:-clem16}"
  image_name="${image_name:-simplelogin-app}"
  
  log_info "Current configuration:"
  echo "  Current version: ${current_version:-<not set>}"
  echo "  Docker repository: $docker_repo"
  echo "  Image name: $image_name"
  echo ""
  
  # Fetch tag from GitHub
  # Use configurable GitHub repo (defaults to upstream simple-login/app)
  local github_repo_user=$(grep "^SL_GITHUB_REPO_USER=" .env 2>/dev/null | cut -d'=' -f2)
  local github_repo_project=$(grep "^SL_GITHUB_REPO_PROJECT=" .env 2>/dev/null | cut -d'=' -f2)
  
  # Use defaults if not set (upstream SimpleLogin repository)
  github_repo_user="${github_repo_user:-simple-login}"
  github_repo_project="${github_repo_project:-app}"
  
  local github_repo="${github_repo_user}/${github_repo_project}"
  local target_tag
  
  if [ -n "$specified_tag" ]; then
    # Verify specified tag exists
    target_tag=$(fetch_latest_github_tag "$github_repo" "$specified_tag")
  else
    # Fetch latest tag
    target_tag=$(fetch_latest_github_tag "$github_repo")
  fi
  
  if [ $? -ne 0 ] || [ -z "$target_tag" ]; then
    log_error "Failed to fetch tag from GitHub"
    log_info "Network issue or GitHub API unavailable"
    exit 1
  fi
  
  # Sanitize the tag to remove any potential log output pollution
  # This handles cases where log messages may have been captured with the tag
  target_tag=$(sanitize_tag "$target_tag")
  
  # Validate the tag format to ensure it's clean and doesn't contain malformed data
  # This prevents using tags like "clem16/simplelogin-app:[INFO] Fetching... v1.0.0"
  if ! validate_tag "$target_tag"; then
    log_error "Tag validation failed after fetching from GitHub"
    log_error "The tag value appears to be malformed or polluted with log output"
    log_error "Cannot proceed with Docker image update"
    exit 1
  fi
  
  log_success "Target GitHub tag: $target_tag"
  echo ""
  
  # Check if already on target version
  if [ "$current_version" = "$target_tag" ]; then
    log_info "Already on target version: $target_tag"
    echo "No update needed."
    return 0
  fi
  
  # Construct Docker image name
  local docker_image="${docker_repo}/${image_name}:${target_tag}"
  
  # Check if Docker image exists, with retry logic
  log_info "Checking Docker image availability with retry logic..."
  echo "  Max retries: $MAX_RETRIES"
  echo "  Retry delay: ${RETRY_DELAY}s"
  echo "  Max wait time: $((MAX_RETRIES * RETRY_DELAY))s"
  echo ""
  
  local retry_count=0
  local image_found=false
  
  while [ $retry_count -lt $MAX_RETRIES ]; do
    if check_docker_image_exists "$docker_image"; then
      image_found=true
      break
    fi
    
    retry_count=$((retry_count + 1))
    if [ $retry_count -lt $MAX_RETRIES ]; then
      log_info "Retry $retry_count/$MAX_RETRIES - waiting ${RETRY_DELAY}s before next attempt..."
      sleep "$RETRY_DELAY"
    fi
  done
  
  echo ""
  
  if [ "$image_found" = false ]; then
    log_warning "Docker image not available after $MAX_RETRIES retries: $docker_image"
    
    # Only attempt fallback for --update-latest, not for --update-tag
    if [ -z "$specified_tag" ]; then
      echo ""
      echo "Attempting fallback to last available Docker tag..."
      echo ""
      
      # Get available tags from Docker registry
      local available_tags=$(get_available_docker_tags "$docker_repo" "$image_name")
      
      if [ -z "$available_tags" ]; then
        log_error "Failed to fetch available Docker tags"
        log_error "Cannot proceed with update"
        exit 1
      fi
      
      # Find the most recent tag that exists
      # Limit search to first 10 tags to avoid excessive API calls
      local fallback_tag=""
      local check_count=0
      local max_checks=10
      
      log_info "Searching for latest available tag (checking up to $max_checks tags)..."
      
      for tag in $available_tags; do
        if [ $check_count -ge $max_checks ]; then
          log_warning "Reached maximum tag check limit ($max_checks)"
          break
        fi
        
        check_count=$((check_count + 1))
        if check_docker_image_exists "${docker_repo}/${image_name}:${tag}"; then
          fallback_tag="$tag"
          break
        fi
      done
      
      if [ -z "$fallback_tag" ]; then
        log_error "No available Docker tags found in registry (checked $check_count tags)"
        log_error "Cannot proceed with update"
        exit 1
      fi
      
      log_warning "Falling back to available tag: $fallback_tag"
      target_tag="$fallback_tag"
      docker_image="${docker_repo}/${image_name}:${target_tag}"
    else
      log_error "Docker image not available: $docker_image"
      log_error "The specified tag may not have been built yet or may not exist in the registry"
      exit 1
    fi
  fi
  
  # Update .env file
  if update_env_version "$target_tag"; then
    echo ""
    log_success "Version update completed successfully!"
    echo ""
    
    # Pull the Docker image
    log_info "Pulling Docker image: $docker_image"
    if docker pull "$docker_image"; then
      log_success "Docker image pulled successfully"
    else
      log_error "Failed to pull Docker image"
      log_warning "You may need to pull the image manually:"
      echo "  docker pull $docker_image"
    fi
  else
    log_error "Failed to update version"
    exit 1
  fi
}

# Function to perform Docker cleanup
perform_cleanup() {
  echo "=========================================="
  echo "Docker Cleanup"
  echo "=========================================="
  
  if [ "$DEEP_CLEANUP" = true ]; then
    echo ""
    echo "⚠️  WARNING: Deep cleanup will remove ALL unused Docker resources system-wide!"
    echo "This includes images, containers, volumes, and networks not in use."
    echo ""
    
    if [ "$AUTO_YES" != true ]; then
      read -p "Are you sure you want to proceed with deep cleanup? (yes/no): " confirmation
      if [ "$confirmation" != "yes" ]; then
        echo "Deep cleanup cancelled."
        exit 0
      fi
    fi
    
    echo "Performing deep cleanup (docker system prune -af --volumes)..."
    docker system prune -af --volumes
    echo "✓ Deep cleanup completed"
  else
    echo "Cleaning up dangling/unused Docker images and volumes..."
    echo ""
    
    # Prune dangling images
    echo "Pruning dangling images..."
    docker image prune -f
    
    # Prune unused volumes (only those not attached to containers)
    echo "Pruning unused volumes..."
    docker volume prune -f
    
    echo "✓ Cleanup completed"
  fi
  
  echo ""
}

# Function to perform fresh install
perform_fresh_install() {
  echo "=========================================="
  echo "⚠️  FRESH INSTALL - DATA WIPE WARNING"
  echo "=========================================="
  echo ""
  echo "This will PERMANENTLY DELETE all data including:"
  echo "  - All database data (PostgreSQL)"
  echo "  - Uploaded files (./upload)"
  echo "  - PGP keys (./pgp)"
  echo "  - DKIM keys (./dkim.key)"
  echo "  - Traefik certificates (Docker volume: traefik-acme)"
  echo "  - Certificate exports (Docker volume: certs)"
  echo "  - Database directory (./db)"
  echo ""
  echo "This action CANNOT be undone!"
  echo ""
  
  if [ "$AUTO_YES" != true ]; then
    read -p "Are you absolutely sure you want to proceed? Type 'yes' to confirm: " confirmation
    if [ "$confirmation" != "yes" ]; then
      echo "Fresh install cancelled."
      exit 0
    fi
    
    echo ""
    read -p "Last chance! Type 'DELETE ALL DATA' to proceed: " final_confirmation
    if [ "$final_confirmation" != "DELETE ALL DATA" ]; then
      echo "Fresh install cancelled."
      exit 0
    fi
  fi
  
  echo ""
  echo "Proceeding with fresh install..."
  echo ""
  
  # Stop and remove all containers, networks, and volumes
  echo "Stopping and removing all containers..."
  docker compose down -v --remove-orphans
  
  # Remove named volumes explicitly
  echo "Removing named volumes..."
  docker volume rm traefik-acme 2>/dev/null || echo "  (traefik-acme volume not found, skipping)"
  docker volume rm certs 2>/dev/null || echo "  (certs volume not found, skipping)"
  
  # Remove bind mount directories
  echo "Removing bind mount directories..."
  [ -d "./db" ] && rm -rf ./db && echo "  ✓ Removed ./db"
  [ -d "./pgp" ] && rm -rf ./pgp && echo "  ✓ Removed ./pgp"
  [ -d "./upload" ] && rm -rf ./upload && echo "  ✓ Removed ./upload"
  [ -f "./dkim.key" ] && rm -f ./dkim.key && echo "  ✓ Removed ./dkim.key"
  
  echo ""
  echo "✓ All data removed successfully"
  echo ""
  echo "Recreating fresh environment..."
  echo ""
  
  # The rest of the script will continue to pull/build images and start containers
}

# Check Docker login status (unless skipped)
if [ "$NO_DOCKER_LOGIN_CHECK" != true ]; then
  if ! check_docker_login; then
    exit 1
  fi
  echo ""
fi

# Execute version update if requested
if [ "$UPDATE_LATEST" = true ]; then
  perform_version_update
  echo ""
elif [ -n "$UPDATE_TAG" ]; then
  perform_version_update "$UPDATE_TAG"
  echo ""
fi

# Execute cleanup if requested
if [ "$CLEANUP_MODE" = true ]; then
  perform_cleanup
fi

# Execute fresh install if requested
if [ "$FRESH_INSTALL" = true ]; then
  perform_fresh_install
fi

# Helper function to extract variable from .env file
get_env_var() {
  grep "^$1=" .env 2>/dev/null | cut -d'=' -f2
}

# Check if .env exists and load it to validate SL_VERSION
if [ ! -f .env ]; then
  echo "ERROR: .env file not found!"
  echo "Please copy .env.example to .env and configure it:"
  echo "  cp .env.example .env"
  exit 1
fi

# Load configuration from .env
SL_VERSION=$(get_env_var "SL_VERSION")
SL_DOCKER_REPO=$(get_env_var "SL_DOCKER_REPO")
SL_IMAGE=$(get_env_var "SL_IMAGE")
SL_CUSTOM_IMAGE=$(get_env_var "SL_CUSTOM_IMAGE")

# Determine the Docker image to use (single source of truth: .env)
if [ -n "$SL_CUSTOM_IMAGE" ]; then
  # Custom image override is set
  DOCKER_IMAGE="$SL_CUSTOM_IMAGE"
else
  # Construct image from components (use defaults if not set)
  DOCKER_REPO="${SL_DOCKER_REPO:-clem16}"
  IMAGE_NAME="${SL_IMAGE:-simplelogin-app}"
  
  # Validate SL_VERSION is set
  if [ -z "$SL_VERSION" ]; then
    echo "ERROR: SL_VERSION is not set in .env file"
    echo "Please set SL_VERSION to your desired Docker image tag"
    exit 1
  fi
  
  DOCKER_IMAGE="$DOCKER_REPO/$IMAGE_NAME:$SL_VERSION"
fi

echo "Using Docker image: $DOCKER_IMAGE"

# Check if the Docker image exists locally
echo "Checking if Docker image exists locally..."
if docker image inspect "$DOCKER_IMAGE" &> /dev/null; then
  echo "✓ Docker image found locally: $DOCKER_IMAGE"
else
  echo "Docker image not found locally. Checking remote registry..."
  
  # Check if image exists on Docker Hub (or other registry)
  # Use docker manifest inspect which works without pulling the image
  if docker manifest inspect "$DOCKER_IMAGE" &> /dev/null; then
    echo "✓ Docker image found on remote registry: $DOCKER_IMAGE"
    echo "Pulling Docker image..."
    docker compose pull
  else
    echo ""
    echo "ERROR: Docker image not found (locally or remotely): $DOCKER_IMAGE"
    echo ""
    echo "Please ensure the image exists by either:"
    echo "  1. Building and pushing the image to the registry"
    echo "  2. Setting an existing image tag in your .env file (SL_VERSION=...)"
    echo ""
    echo "TODO: Consider automating the build/push process from upstream images"
    echo "      See: https://github.com/simple-login/app for upstream source"
    exit 1
  fi
fi

## Build postfix image from local Dockerfile
echo "Building postfix image from local Dockerfile..."
docker compose build postfix

# Run docker compose with or without detach flag based on mode
if [ "$FOREGROUND_MODE" = true ]; then
  echo "Starting containers in foreground mode..."
  docker compose up --remove-orphans $@
else
  echo "Starting containers in detached mode..."
  docker compose up --remove-orphans --detach $@
fi
