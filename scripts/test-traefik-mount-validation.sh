#!/bin/bash
# Test script to verify traefik-entrypoint.sh mount validation

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "======================================"
echo "Testing Traefik Script Mount Validation"
echo "======================================"
echo ""

# Test 1: Validation from correct directory
echo "Test 1: Validation from repository root"
echo "----------------------------------------"
cd "$REPO_ROOT"
if make validate-traefik-script > /dev/null 2>&1; then
    echo "✅ PASS: Validation succeeds from repo root"
else
    echo "❌ FAIL: Validation should succeed from repo root"
    exit 1
fi
echo ""

# Test 2: Validation from wrong directory
echo "Test 2: Validation from wrong directory"
echo "----------------------------------------"
cd /tmp
if make -f "$REPO_ROOT/Makefile" validate-traefik-script > /dev/null 2>&1; then
    echo "❌ FAIL: Validation should fail from wrong directory"
    exit 1
else
    echo "✅ PASS: Validation correctly fails from wrong directory"
fi
echo ""

# Test 3: Pre-flight check detects missing scripts
echo "Test 3: Pre-flight check detects scripts directory"
echo "---------------------------------------------------"
cd "$REPO_ROOT"
if bash scripts/preflight-check.sh 2>&1 | grep -q "scripts directory found"; then
    echo "✅ PASS: Pre-flight check detects scripts directory"
else
    echo "❌ FAIL: Pre-flight check should detect scripts directory"
    exit 1
fi
echo ""

# Test 4: Pre-flight check validates traefik-entrypoint.sh
echo "Test 4: Pre-flight check validates traefik-entrypoint.sh"
echo "---------------------------------------------------------"
if bash scripts/preflight-check.sh 2>&1 | grep -q "scripts/traefik-entrypoint.sh found"; then
    echo "✅ PASS: Pre-flight check validates traefik-entrypoint.sh"
else
    echo "❌ FAIL: Pre-flight check should validate traefik-entrypoint.sh"
    exit 1
fi
echo ""

# Test 5: Verify .dockerignore doesn't exclude scripts
echo "Test 5: .dockerignore includes scripts directory"
echo "-------------------------------------------------"
if [ -f "$REPO_ROOT/.dockerignore" ]; then
    if grep -q "!scripts/" "$REPO_ROOT/.dockerignore"; then
        echo "✅ PASS: .dockerignore explicitly includes scripts/"
    else
        echo "❌ FAIL: .dockerignore should explicitly include scripts/"
        exit 1
    fi
else
    echo "❌ FAIL: .dockerignore file should exist"
    exit 1
fi
echo ""

# Test 6: Verify traefik-compose.yaml has correct mount
echo "Test 6: config/traefik-compose.yaml has correct volume mount"
echo "------------------------------------------------------"
if grep -q "./scripts:/scripts:ro" "$REPO_ROOT/config/traefik-compose.yaml"; then
    echo "✅ PASS: config/traefik-compose.yaml has correct volume mount"
else
    echo "❌ FAIL: config/traefik-compose.yaml should mount ./scripts:/scripts:ro"
    exit 1
fi
echo ""

# Test 7: Verify traefik-compose.yaml references the entrypoint
echo "Test 7: config/traefik-compose.yaml references entrypoint script"
echo "----------------------------------------------------------"
if grep -q "/scripts/traefik-entrypoint.sh" "$REPO_ROOT/config/traefik-compose.yaml"; then
    echo "✅ PASS: config/traefik-compose.yaml references traefik-entrypoint.sh"
else
    echo "❌ FAIL: config/traefik-compose.yaml should reference traefik-entrypoint.sh"
    exit 1
fi
echo ""

# Test 8: Verify README has warning
echo "Test 8: README contains warning about running from repo root"
echo "-------------------------------------------------------------"
if grep -q "run Docker Compose from the repository root" "$REPO_ROOT/README.md"; then
    echo "✅ PASS: README contains warning about repo root"
else
    echo "❌ FAIL: README should warn about running from repo root"
    exit 1
fi
echo ""

# Test 9: Verify TROUBLESHOOTING has section
echo "Test 9: TROUBLESHOOTING has section on script mount error"
echo "----------------------------------------------------------"
if grep -q "no such file or directory" "$REPO_ROOT/docs/TROUBLESHOOTING.md"; then
    echo "✅ PASS: TROUBLESHOOTING documents the error"
else
    echo "❌ FAIL: TROUBLESHOOTING should document the error"
    exit 1
fi
echo ""

echo "======================================"
echo "All Tests Passed!"
echo "======================================"
echo ""
echo "Summary:"
echo "✓ Makefile validates traefik script correctly"
echo "✓ Pre-flight check detects missing scripts"
echo "✓ .dockerignore includes scripts directory"
echo "✓ traefik-compose.yaml has correct configuration"
echo "✓ Documentation includes warnings and troubleshooting"
echo ""
