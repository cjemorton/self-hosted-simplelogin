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

# Check if .env exists and load it to validate SL_VERSION
if [ ! -f .env ]; then
  echo "ERROR: .env file not found!"
  echo "Please copy .env.example to .env and configure it:"
  echo "  cp .env.example .env"
  exit 1
fi

# Load SL_VERSION from .env for validation
source <(grep "^SL_VERSION=" .env)

# Get expected version from .env.example
EXPECTED_VERSION=$(grep "^SL_VERSION=" .env.example | cut -d'=' -f2)

# Validate SL_VERSION for custom fork
if [ -n "$SL_VERSION" ] && [ "$SL_VERSION" != "$EXPECTED_VERSION" ]; then
  echo "ERROR: Incorrect SL_VERSION detected: $SL_VERSION"
  echo "This fork uses a custom Docker image: clem16/simplelogin-app:$EXPECTED_VERSION"
  echo ""
  echo "Please update your .env file:"
  echo "  SL_VERSION=$EXPECTED_VERSION"
  echo ""
  echo "Note: The official SimpleLogin image (simplelogin/app-ci) versions like v4.70.0"
  echo "      are not compatible with this fork's custom image (clem16/simplelogin-app)."
  exit 1
elif [ -z "$SL_VERSION" ]; then
  echo "ERROR: SL_VERSION is not set in .env file"
  echo "Please set: SL_VERSION=$EXPECTED_VERSION"
  exit 1
fi

echo "✓ Using correct Docker image version: clem16/simplelogin-app:$SL_VERSION"

## Pull the latest docker images before starting
echo "Pulling latest Docker images..."
docker compose pull

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
