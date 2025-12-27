#!/bin/bash

# GemGuard API Test Script
# Run: chmod +x test_curl.sh && ./test_curl.sh

BASE_URL="${GEMGUARD_URL:-http://localhost:3000}"

echo "=========================================="
echo "GemGuard API Test Script"
echo "Base URL: $BASE_URL"
echo "=========================================="

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

test_endpoint() {
  local name="$1"
  local url="$2"
  local expected_status="$3"
  local extra_args="${4:-}"

  echo -e "\n${YELLOW}Testing: $name${NC}"
  echo "URL: $url"

  status=$(curl -s -o /dev/null -w "%{http_code}" $extra_args "$url")

  if [ "$status" = "$expected_status" ]; then
    echo -e "Status: ${GREEN}$status (expected $expected_status) ✓${NC}"
  else
    echo -e "Status: ${RED}$status (expected $expected_status) ✗${NC}"
  fi
}

echo ""
echo "=========================================="
echo "1. Health Check"
echo "=========================================="

test_endpoint "Health Check" "$BASE_URL/up" "200"

echo ""
echo "=========================================="
echo "2. Specs Endpoints (RubyGems-compatible)"
echo "=========================================="

# These will trigger a sync if specs aren't cached
test_endpoint "All Specs" "$BASE_URL/specs.4.8.gz" "200"
test_endpoint "Latest Specs" "$BASE_URL/latest_specs.4.8.gz" "200"
test_endpoint "Prerelease Specs" "$BASE_URL/prerelease_specs.4.8.gz" "200"

echo ""
echo "=========================================="
echo "3. Gem Download Endpoints"
echo "=========================================="

# Test gem that doesn't exist
test_endpoint "Non-existent gem" "$BASE_URL/gems/nonexistent-1.0.0.gem" "404"

# Test gem that exists on RubyGems (should be fetched and served)
test_endpoint "Rails gem (fetched from upstream)" "$BASE_URL/gems/rails-1.0.0.gem" "200"

echo ""
echo "=========================================="
echo "4. Gemspec Endpoints"
echo "=========================================="

test_endpoint "Non-existent gemspec" "$BASE_URL/quick/Marshal.4.8/nonexistent-1.0.0.gemspec.rz" "404"

echo ""
echo "=========================================="
echo "5. Admin Interface"
echo "=========================================="

test_endpoint "Admin Dashboard" "$BASE_URL/admin" "200"
test_endpoint "Admin Gem Packages" "$BASE_URL/admin/gem_packages" "200"
test_endpoint "Admin Quarantine Rules" "$BASE_URL/admin/quarantine_rules" "200"
test_endpoint "Admin Audit Logs" "$BASE_URL/admin/audit_logs" "200"
test_endpoint "Admin Settings" "$BASE_URL/admin/settings" "200"

echo ""
echo "=========================================="
echo "6. Verbose Examples"
echo "=========================================="

echo -e "\n${YELLOW}Specs file info:${NC}"
curl -sI "$BASE_URL/specs.4.8.gz" | head -10

echo -e "\n${YELLOW}Admin dashboard preview:${NC}"
curl -s "$BASE_URL/admin" | grep -o '<title>.*</title>'

echo ""
echo "=========================================="
echo "Done!"
echo "=========================================="
