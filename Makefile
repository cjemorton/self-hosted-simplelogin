.PHONY: help check preflight-check start stop restart clean test logs

# Default target
.DEFAULT_GOAL := help

help: ## Show this help message
	@echo "SimpleLogin Makefile - Available targets:"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'
	@echo ""
	@echo "Common workflows:"
	@echo "  make check          - Run all pre-flight checks before starting"
	@echo "  make start          - Start SimpleLogin (after running 'make check')"
	@echo "  make restart        - Restart all services"
	@echo "  make logs           - Follow logs from all services"
	@echo "  make stop           - Stop all services"

check: ## Run pre-flight checks to ensure system is ready
	@echo "Running pre-flight checks..."
	@echo ""
	@if [ ! -f "scripts/preflight-check.sh" ]; then \
		echo "ERROR: scripts/preflight-check.sh not found"; \
		echo "Ensure you're running from the repository root"; \
		exit 1; \
	fi
	@bash scripts/preflight-check.sh

preflight-check: check ## Alias for 'check' target

validate-traefik-script: ## Validate traefik-entrypoint.sh exists and is accessible
	@echo "Validating Traefik entrypoint script..."
	@if [ ! -d "scripts" ]; then \
		echo "ERROR: scripts directory not found"; \
		echo "You must run Docker Compose from the repository root"; \
		echo "Current directory: $$(pwd)"; \
		exit 1; \
	fi
	@if [ ! -f "scripts/traefik-entrypoint.sh" ]; then \
		echo "ERROR: scripts/traefik-entrypoint.sh not found"; \
		echo "This file is required for Traefik to start"; \
		echo "Expected location: $$(pwd)/scripts/traefik-entrypoint.sh"; \
		exit 1; \
	fi
	@if [ ! -x "scripts/traefik-entrypoint.sh" ]; then \
		echo "WARNING: scripts/traefik-entrypoint.sh is not executable"; \
		echo "Making it executable..."; \
		chmod +x scripts/traefik-entrypoint.sh; \
	fi
	@echo "✓ Traefik entrypoint script validation passed"
	@echo "  Location: $$(pwd)/scripts/traefik-entrypoint.sh"
	@echo ""

start: validate-traefik-script ## Start SimpleLogin services
	@echo "Starting SimpleLogin..."
	bash scripts/up.sh

up: start ## Alias for 'start' target

stop: ## Stop all SimpleLogin services
	@echo "Stopping SimpleLogin..."
	bash scripts/stop.sh

down: stop ## Alias for 'stop' target

restart: ## Restart all SimpleLogin services
	@echo "Restarting SimpleLogin..."
	bash scripts/stop.sh
	bash scripts/up.sh

logs: ## Follow logs from all services
	docker compose logs -f

test-traefik-script: ## Run tests for traefik-entrypoint.sh
	@if [ ! -f "scripts/test-traefik-entrypoint.sh" ]; then \
		echo "ERROR: scripts/test-traefik-entrypoint.sh not found"; \
		exit 1; \
	fi
	@bash scripts/test-traefik-entrypoint.sh

test: test-traefik-script ## Run all tests

clean: ## Clean up stopped containers and unused volumes
	@echo "Cleaning up Docker resources..."
	docker compose down -v --remove-orphans
	@echo "✓ Cleanup complete"

.PHONY: validate-traefik-script test-traefik-script
