#!/bin/env bash

## use `--remove-orphans` to remove nginx container from previous versions, to free up ports 80/443 for traefik

## Pull the latest docker images before starting
echo "Pulling latest Docker images..."
docker compose pull

docker compose up --remove-orphans --detach $@
