#!/usr/bin/env bash
#
# test-tag-pollution-fix.sh - Test the fix for tag pollution bug
#
# This test demonstrates the bug that was fixed where log output
# would pollute the tag variable, causing malformed Docker image references

set -euo pipefail

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "=========================================="
echo "Testing Tag Pollution Fix"
echo "=========================================="
echo ""

# Change to repository root
cd "$(dirname "$0")/.." || exit 1

echo -e "${BLUE}[INFO]${NC} Extracting functions from up.sh..."

# Extract the functions we need to test
source <(sed -n '/^validate_tag()/,/^}/p' scripts/up.sh)
source <(sed -n '/^sanitize_tag()/,/^}/p' scripts/up.sh)

# Override log_error to avoid dependency issues
log_error() { echo "ERROR: $*" >&2; }

echo -e "${BLUE}[INFO]${NC} Testing tag validation and sanitization..."
echo ""

# Test 1: Simulate the bug scenario
echo "Test 1: Simulating the original bug scenario"
echo "-------------------------------------------"
MALFORMED_TAG="[INFO] Fetching latest tag from GitHub: cjemorton/simplelogin-app... v2026.02.02-staging-test-04"
echo "Malformed tag (as captured by command substitution with log output):"
echo "  '$MALFORMED_TAG'"
echo ""

# This would have failed in the old code, creating a Docker image name like:
# clem16/simplelogin-app:[INFO] Fetching latest tag from GitHub: cjemorton/simplelogin-app... v2026.02.02-staging-test-04
echo "Validating malformed tag..."
# The tag should fail validation because it contains spaces
if ! validate_tag "$MALFORMED_TAG" 2>/dev/null; then
  echo -e "${GREEN}✓ PASS:${NC} Malformed tag correctly detected and rejected"
else
  echo -e "${RED}✗ FAIL:${NC} Malformed tag should have been rejected"
  exit 1
fi
echo ""

# Test 2: Sanitization should extract the clean tag
echo "Test 2: Sanitizing the polluted tag"
echo "-----------------------------------"
CLEAN_TAG=$(sanitize_tag "$MALFORMED_TAG")
echo "Sanitized tag: '$CLEAN_TAG'"
echo ""

if [ "$CLEAN_TAG" = "v2026.02.02-staging-test-04" ]; then
  echo -e "${GREEN}✓ PASS:${NC} Tag successfully sanitized"
else
  echo -e "${RED}✗ FAIL:${NC} Tag sanitization failed. Got: '$CLEAN_TAG'"
  exit 1
fi
echo ""

# Test 3: Sanitized tag should pass validation
echo "Test 3: Validating the sanitized tag"
echo "------------------------------------"
if validate_tag "$CLEAN_TAG" 2>/dev/null; then
  echo -e "${GREEN}✓ PASS:${NC} Sanitized tag passes validation"
else
  echo -e "${RED}✗ FAIL:${NC} Sanitized tag should pass validation"
  exit 1
fi
echo ""

# Test 4: Clean tag from the start
echo "Test 4: Clean tag validation"
echo "----------------------------"
ORIGINAL_CLEAN_TAG="v2026.02.02-staging-test-04"
if validate_tag "$ORIGINAL_CLEAN_TAG" 2>/dev/null; then
  echo -e "${GREEN}✓ PASS:${NC} Clean tag passes validation"
else
  echo -e "${RED}✗ FAIL:${NC} Clean tag should pass validation"
  exit 1
fi
echo ""

# Test 5: Tag with newlines (explicit newline character)
echo "Test 5: Tag with newlines (multi-line pollution)"
echo "------------------------------------------------"
# Create a tag with an actual newline in it
MULTILINE_TAG=$'line1\nline2'
if ! validate_tag "$MULTILINE_TAG" 2>/dev/null; then
  echo -e "${GREEN}✓ PASS:${NC} Multi-line tag correctly rejected"
else
  echo -e "${RED}✗ FAIL:${NC} Multi-line tag should be rejected"
  exit 1
fi
echo ""

# Test 6: Empty tag
echo "Test 6: Empty tag validation"
echo "----------------------------"
if ! validate_tag "" 2>/dev/null; then
  echo -e "${GREEN}✓ PASS:${NC} Empty tag correctly rejected"
else
  echo -e "${RED}✗ FAIL:${NC} Empty tag should be rejected"
  exit 1
fi
echo ""

# Test 7: Tag with invalid characters
echo "Test 7: Tag with invalid characters"
echo "-----------------------------------"
INVALID_TAG="v2026.02.02@latest"
if ! validate_tag "$INVALID_TAG" 2>/dev/null; then
  echo -e "${GREEN}✓ PASS:${NC} Tag with invalid characters correctly rejected"
else
  echo -e "${RED}✗ FAIL:${NC} Tag with invalid characters should be rejected"
  exit 1
fi
echo ""

echo "=========================================="
echo -e "${GREEN}All tests passed!${NC}"
echo "=========================================="
echo ""
echo "Summary:"
echo "  ✓ Malformed tags are detected and rejected"
echo "  ✓ Tag sanitization extracts clean values"
echo "  ✓ Sanitized tags pass validation"
echo "  ✓ Clean tags work correctly"
echo "  ✓ Multi-line pollution is detected"
echo "  ✓ Empty tags are rejected"
echo "  ✓ Invalid characters are detected"
echo ""
echo "The fix successfully prevents the infinite retry loop bug"
echo "by ensuring only clean tag values are used for Docker image references."
