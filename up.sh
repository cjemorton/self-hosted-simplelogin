#!/bin/env bash

## use `--remove-orphans` to remove nginx container from previous versions, to free up ports 80/443 for traefik

# Check if .env exists and load it to validate SL_VERSION
if [ ! -f .env ]; then
  echo "ERROR: .env file not found!"
  echo "Please copy .env.example to .env and configure it:"
  echo "  cp .env.example .env"
  exit 1
fi

# Load SL_VERSION from .env for validation
source <(grep "^SL_VERSION=" .env)

# Validate SL_VERSION for custom fork
EXPECTED_VERSION="v2026.02.02-staging-test-02"
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

docker compose up --remove-orphans --detach $@
