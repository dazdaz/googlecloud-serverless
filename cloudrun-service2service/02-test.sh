#!/bin/bash
# =============================================================================
# Cloud Run Service-to-Service Demo - Test Script
# =============================================================================
# This script tests the service-to-service communication between
# the Gateway, User, and Order services using internal networking.
#
# Service Mesh Patterns Tested:
# 1. Gateway → User Service
# 2. Gateway → Order Service
# 3. Gateway → User Service → Order Service (mesh pattern)
# =============================================================================

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
REGION="${GCP_REGION:-us-central1}"

# Track test progress
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Cleanup function for Ctrl+C handling
cleanup_on_interrupt() {
    echo ""
    echo -e "${YELLOW}========================================${NC}"
    echo -e "${YELLOW}Testing interrupted by user${NC}"
    echo -e "${YELLOW}========================================${NC}"
    echo ""
    echo -e "Tests run: ${TESTS_RUN}"
    echo -e "Tests passed: ${GREEN}${TESTS_PASSED}${NC}"
    echo -e "Tests failed: ${RED}${TESTS_FAILED}${NC}"
    exit 130
}

# Set up trap for Ctrl+C (SIGINT) and SIGTERM
trap cleanup_on_interrupt SIGINT SIGTERM

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Cloud Run Service-to-Service Demo${NC}"
echo -e "${BLUE}Testing Service Mesh Communication${NC}"
echo -e "${BLUE}========================================${NC}"
echo -e "${YELLOW}Press Ctrl+C at any time to cancel${NC}"
echo ""

# Get service URLs
GATEWAY_URL=$(gcloud run services describe gateway-service \
    --region "$REGION" \
    --format 'value(status.url)' 2>/dev/null)

USER_URL=$(gcloud run services describe user-service \
    --region "$REGION" \
    --format 'value(status.url)' 2>/dev/null)

ORDER_URL=$(gcloud run services describe order-service \
    --region "$REGION" \
    --format 'value(status.url)' 2>/dev/null)

if [ -z "$GATEWAY_URL" ]; then
    echo -e "${RED}Error: Gateway service not found. Run 01-setup.sh first.${NC}"
    exit 1
fi

echo -e "${GREEN}Service URLs:${NC}"
echo -e "  Gateway:  $GATEWAY_URL (public)"
echo -e "  User:     $USER_URL (internal only)"
echo -e "  Order:    $ORDER_URL (internal only)"
echo ""
echo -e "${GREEN}Service Mesh Configuration:${NC}"
echo -e "  Gateway  → User Service  (via VPC + OIDC)"
echo -e "  Gateway  → Order Service (via VPC + OIDC)"
echo -e "  User Service → Order Service (via VPC + OIDC)"
echo ""

# Function to make a request and display results
make_request() {
    local description="$1"
    local method="$2"
    local url="$3"
    local data="$4"
    local expect_failure="${5:-false}"
    
    ((TESTS_RUN++))
    
    echo -e "${CYAN}----------------------------------------${NC}"
    echo -e "${CYAN}Test $TESTS_RUN: $description${NC}"
    echo -e "${CYAN}----------------------------------------${NC}"
    echo -e "${YELLOW}$method $url${NC}"
    
    if [ -n "$data" ]; then
        echo -e "${YELLOW}Body: $data${NC}"
    fi
    echo ""
    
    if [ "$method" == "GET" ]; then
        response=$(curl -s -w "\n%{http_code}" --connect-timeout 10 "$url" 2>&1) || true
    else
        response=$(curl -s -w "\n%{http_code}" --connect-timeout 10 -X "$method" -H "Content-Type: application/json" -d "$data" "$url" 2>&1) || true
    fi
    
    http_code=$(echo "$response" | tail -n1)
    body=$(echo "$response" | sed \$d)
    
    if [ "$expect_failure" == "true" ]; then
        if [ "$http_code" == "403" ] || [ "$http_code" == "000" ] || [ "$http_code" == "404" ]; then
            echo -e "${GREEN}✓ Access correctly denied (HTTP $http_code)${NC}"
            ((TESTS_PASSED++))
        else
            echo -e "${RED}✗ Expected failure but got HTTP $http_code${NC}"
            ((TESTS_FAILED++))
        fi
    else
        if [ "$http_code" -ge 200 ] && [ "$http_code" -lt 300 ]; then
            echo -e "${GREEN}✓ Status: $http_code${NC}"
            ((TESTS_PASSED++))
        else
            echo -e "${RED}✗ Status: $http_code${NC}"
            ((TESTS_FAILED++))
        fi
        
        echo -e "${GREEN}Response:${NC}"
        echo "$body" | jq . 2>/dev/null || echo "$body"
    fi
    echo ""
}

# =============================================================================
# Basic Tests
# =============================================================================
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}BASIC CONNECTIVITY TESTS${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

make_request "Gateway Health Check" "GET" "$GATEWAY_URL/"

# =============================================================================
# Gateway -> Service Tests
# =============================================================================
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}GATEWAY → SERVICE TESTS${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

make_request "Gateway → User Service: Get All Users" "GET" "$GATEWAY_URL/api/users"

make_request "Gateway → User Service: Get Specific User" "GET" "$GATEWAY_URL/api/users/user-001"

make_request "Gateway → Order Service: Get All Orders" "GET" "$GATEWAY_URL/api/orders"

make_request "Gateway → [User + Order]: Aggregate Data" "GET" "$GATEWAY_URL/api/aggregate"

# =============================================================================
# Service Mesh Tests (User Service -> Order Service)
# =============================================================================
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}SERVICE MESH TESTS (Nested Calls)${NC}"
echo -e "${BLUE}========================================${NC}"
echo -e "${YELLOW}Testing: Gateway → User Service → Order Service${NC}"
echo ""

make_request "SERVICE MESH: Get User Orders via User Service" "GET" "$GATEWAY_URL/api/user-orders/user-001"

make_request "DIRECT: Get User Orders via Gateway (comparison)" "GET" "$GATEWAY_URL/api/user-orders-direct/user-001"

# =============================================================================
# Write Operations
# =============================================================================
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}WRITE OPERATION TESTS${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

make_request "Create New Order via Gateway" "POST" "$GATEWAY_URL/api/orders" \
    '{"userId": "user-002", "items": [{"product": "Test Product", "quantity": 2, "price": 25.99}]}'

# =============================================================================
# Security Tests
# =============================================================================
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}SECURITY TESTS (Direct Access Should Fail)${NC}"
echo -e "${BLUE}========================================${NC}"
echo -e "${YELLOW}Testing that internal services reject direct internet access${NC}"
echo ""

make_request "Direct Access to User Service (should fail)" "GET" "$USER_URL/users" "" "true"
make_request "Direct Access to Order Service (should fail)" "GET" "$ORDER_URL/orders" "" "true"

# Remove trap after completion
trap - SIGINT SIGTERM

# =============================================================================
# Summary
# =============================================================================
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Test Summary${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo -e "Tests run:    ${TESTS_RUN}"
echo -e "Tests passed: ${GREEN}${TESTS_PASSED}${NC}"
echo -e "Tests failed: ${RED}${TESTS_FAILED}${NC}"
echo ""

if [ "$TESTS_FAILED" -eq 0 ]; then
    echo -e "${GREEN}All tests passed! ✓${NC}"
else
    echo -e "${RED}Some tests failed! ✗${NC}"
fi

echo ""
echo -e "${GREEN}Service Mesh Communication Flow:${NC}"
echo ""
echo "  ┌──────────────┐"
echo "  │   Internet   │"
echo "  └──────┬───────┘"
echo "         │ HTTPS"
echo "         ▼"
echo "  ┌──────────────────┐"
echo "  │  Gateway Service │"
echo "  │     (Python)     │"
echo "  └────────┬─────────┘"
echo "           │"
echo "    ┌──────┴───────┐"
echo "    │ VPC Connector │"
echo "    └──────┬───────┘"
echo "           │ OIDC Auth"
echo "    ┌──────┴───────────────────────┐"
echo "    │                              │"
echo "    ▼                              ▼"
echo "  ┌──────────────────┐   ┌──────────────────┐"
echo "  │   User Service   │──▶│  Order Service   │"
echo "  │       (Go)       │   │    (Node.js)     │"
echo "  │   OIDC Token     │   │                  │"
echo "  └──────────────────┘   └──────────────────┘"
echo ""
echo -e "${GREEN}Key Points Demonstrated:${NC}"
echo "  1. Gateway accepts public requests"
echo "  2. Gateway calls User & Order services via VPC + OIDC"
echo "  3. User Service calls Order Service via VPC + OIDC (mesh)"
echo "  4. All internal traffic stays within Google's network"
echo "  5. Direct internet access to internal services is blocked"
echo ""
echo -e "${GREEN}Gateway URL for further testing: ${GATEWAY_URL}${NC}"

# Exit with appropriate code
if [ "$TESTS_FAILED" -gt 0 ]; then
    exit 1
fi