#!/usr/bin/env bash

## use `--remove-orphans` to remove nginx container from previous versions, to free up ports 80/443 for traefik
##
## Usage:
##   ./up.sh       - Start containers in detached mode (background, default)
##   ./up.sh -f    - Start containers in foreground mode (shows logs on screen)
##
## Options:
##   -f    Run docker compose in foreground mode (no -d flag)
##   -h    Show this help message
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

show_usage() {
  echo "Usage: ./up.sh [OPTIONS]"
  echo ""
  echo "Start SimpleLogin containers using docker compose"
  echo ""
  echo "Options:"
  echo "  -f    Run docker compose in foreground mode (shows logs on screen)"
  echo "  -h    Show this help message"
  echo ""
  echo "Docker Image Validation:"
  echo "  This script uses SL_VERSION from .env as the single source of truth."
  echo "  It checks for image existence (local first, then remote) before starting."
  echo ""
  echo "Examples:"
  echo "  ./up.sh       # Start in detached mode (background)"
  echo "  ./up.sh -f    # Start in foreground mode"
  exit 0
}

while getopts "fh" opt; do
  case $opt in
    f)
      FOREGROUND_MODE=true
      ;;
    h)
      show_usage
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
