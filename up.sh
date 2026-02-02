#!/usr/bin/env bash

## use `--remove-orphans` to remove nginx container from previous versions, to free up ports 80/443 for traefik
##
## Usage:
##   ./up.sh       - Start containers in detached mode (background, default)
##   ./up.sh -f    - Start containers in foreground mode (shows logs on screen)
##   ./up.sh -c    - Cleanup dangling/unused Docker images and volumes before starting
##   ./up.sh -r    - Fresh install: wipe all data and start from scratch (requires confirmation)
##
## Options:
##   -f, --foreground        Run docker compose in foreground mode (no -d flag)
##   -c, --cleanup           Cleanup dangling/unused Docker images and volumes
##       --deep-cleanup      Perform deep cleanup (system prune with volumes) - USE WITH CAUTION
##   -r, --fresh             Fresh install: stop containers, remove volumes, start fresh
##   -y, --yes               Skip confirmation prompts (for automation)
##   -h, --help              Show this help message
##
## Docker Image Validation:
##   This script uses SL_VERSION from .env as the single source of truth for Docker versioning.
##   Before starting:
##     1. Checks if the image exists locally (no remote calls if found)
##     2. If not local, checks the remote Docker registry (Docker Hub)
##     3. If not found anywhere, prints a clear error with instructions
##
##   TODO: Consider automating the build/push process from upstream SimpleLogin images
##         to simplify version management and reduce manual intervention.

# Parse command line options
FOREGROUND_MODE=false
CLEANUP_MODE=false
DEEP_CLEANUP=false
FRESH_INSTALL=false
AUTO_YES=false

show_usage() {
  echo "Usage: ./up.sh [OPTIONS]"
  echo ""
  echo "Start SimpleLogin containers using docker compose"
  echo ""
  echo "Options:"
  echo "  -f, --foreground        Run docker compose in foreground mode (shows logs on screen)"
  echo "  -c, --cleanup           Cleanup dangling/unused Docker images and volumes before starting"
  echo "      --deep-cleanup      Perform deep cleanup (system prune with volumes) - USE WITH CAUTION"
  echo "  -r, --fresh             Fresh install: stop containers, remove volumes, start fresh"
  echo "  -y, --yes               Skip confirmation prompts (for automation)"
  echo "  -h, --help              Show this help message"
  echo ""
  echo "Docker Image Validation:"
  echo "  This script uses SL_VERSION from .env as the single source of truth."
  echo "  It checks for image existence (local first, then remote) before starting."
  echo ""
  echo "Examples:"
  echo "  ./up.sh                 # Start in detached mode (background)"
  echo "  ./up.sh -f              # Start in foreground mode"
  echo "  ./up.sh -c              # Cleanup unused Docker resources, then start"
  echo "  ./up.sh --deep-cleanup  # Deep cleanup (removes ALL unused Docker data)"
  echo "  ./up.sh -r              # Fresh install (prompts for confirmation)"
  echo "  ./up.sh -r -y           # Fresh install (no confirmation, for automation)"
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
