#!/bin/bash
# =============================================================================
# Cloud Run Service-to-Service Demo - Cleanup Script
# =============================================================================
# This script removes all resources created by the demo, including:
# - Cloud Run services
# - VPC Connector
# - Service Account
# - Container images
# =============================================================================

# Don't exit on error - we want to continue cleanup even if some parts fail
set +e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
REGION="${GCP_REGION:-us-central1}"
SERVICE_ACCOUNT_NAME="cloudrun-s2s-invoker"
VPC_CONNECTOR_NAME="s2s-connector"

# Service names
GATEWAY_SERVICE="gateway-service"
USER_SERVICE="user-service"
ORDER_SERVICE="order-service"

# Handle interrupt
handle_interrupt() {
    echo ""
    echo -e "${YELLOW}========================================${NC}"
    echo -e "${YELLOW}Cleanup interrupted by user${NC}"
    echo -e "${YELLOW}========================================${NC}"
    echo ""
    echo -e "${YELLOW}Run this script again to complete cleanup.${NC}"
    exit 130
}

trap handle_interrupt SIGINT SIGTERM

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Cloud Run Service-to-Service Demo${NC}"
echo -e "${BLUE}Cleanup Script${NC}"
echo -e "${BLUE}========================================${NC}"
echo -e "${YELLOW}Press Ctrl+C at any time to cancel${NC}"
echo ""

if [ -z "$PROJECT_ID" ]; then
    echo -e "${RED}Error: No GCP project configured.${NC}"
    echo "Run: gcloud config set project YOUR_PROJECT_ID"
    exit 1
fi

echo "Project ID: $PROJECT_ID"
echo "Region: $REGION"
echo ""

# Confirmation prompt
read -p "Are you sure you want to delete all demo resources? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}Cleanup cancelled.${NC}"
    exit 0
fi
echo ""

# Delete Cloud Run services - these delete quickly
echo -e "${YELLOW}Deleting Cloud Run services...${NC}"

for SERVICE in $GATEWAY_SERVICE $USER_SERVICE $ORDER_SERVICE; do
    if gcloud run services describe "$SERVICE" --region "$REGION" &>/dev/null 2>&1; then
        echo "  Deleting $SERVICE..."
        if gcloud run services delete "$SERVICE" --region "$REGION" --quiet 2>&1; then
            echo -e "  ${GREEN}$SERVICE deleted${NC}"
        else
            echo -e "  ${YELLOW}Failed to delete $SERVICE - may not exist${NC}"
        fi
    else
        echo -e "  ${YELLOW}$SERVICE not found - skipping${NC}"
    fi
done
echo ""

# Delete VPC Connector
echo -e "${YELLOW}Deleting VPC Connector...${NC}"

# Check status first
CONNECTOR_STATUS=$(gcloud compute networks vpc-access connectors describe "$VPC_CONNECTOR_NAME" \
    --region "$REGION" \
    --format='value(state)' 2>/dev/null || echo "NOT_FOUND")

if [ "$CONNECTOR_STATUS" = "NOT_FOUND" ]; then
    echo -e "  ${YELLOW}VPC Connector not found - skipping${NC}"
elif [ "$CONNECTOR_STATUS" = "DELETING" ]; then
    echo -e "  ${YELLOW}VPC Connector is already deleting. Waiting for completion...${NC}"
    
    # Wait loop
    while true; do
        STATUS=$(gcloud compute networks vpc-access connectors describe "$VPC_CONNECTOR_NAME" \
            --region "$REGION" \
            --format='value(state)' 2>/dev/null || echo "NOT_FOUND")
        
        if [ "$STATUS" = "NOT_FOUND" ]; then
            echo ""
            echo -e "  ${GREEN}VPC Connector deleted${NC}"
            break
        fi
        
        echo -n "."
        sleep 5
    done
else
    echo "  Deleting $VPC_CONNECTOR_NAME..."
    echo "  Note: VPC connector deletion takes 1-2 minutes"
    
    # Sync delete (wait for completion)
    if gcloud compute networks vpc-access connectors delete "$VPC_CONNECTOR_NAME" \
        --region "$REGION" \
        --quiet 2>&1; then
        echo -e "  ${GREEN}VPC Connector deleted${NC}"
    else
        echo -e "  ${YELLOW}VPC Connector deletion failed or timed out${NC}"
        echo "  Check status: gcloud compute networks vpc-access connectors list --region $REGION"
    fi
fi
echo ""

# Delete service account
echo -e "${YELLOW}Deleting service account...${NC}"
SERVICE_ACCOUNT_EMAIL="${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

if gcloud iam service-accounts describe "$SERVICE_ACCOUNT_EMAIL" &>/dev/null 2>&1; then
    echo "  Deleting $SERVICE_ACCOUNT_EMAIL..."
    if gcloud iam service-accounts delete "$SERVICE_ACCOUNT_EMAIL" --quiet 2>&1; then
        echo -e "  ${GREEN}Service account deleted${NC}"
    else
        echo -e "  ${YELLOW}Failed to delete service account${NC}"
    fi
else
    echo -e "  ${YELLOW}Service account not found - skipping${NC}"
fi
echo ""

# Delete container images from Artifact Registry
echo -e "${YELLOW}Deleting container images...${NC}"

for SERVICE in $GATEWAY_SERVICE $USER_SERVICE $ORDER_SERVICE; do
    IMAGE_PATH="${REGION}-docker.pkg.dev/${PROJECT_ID}/cloud-run-source-deploy/${SERVICE}"
    
    if gcloud artifacts docker images list "$IMAGE_PATH" &>/dev/null 2>&1; then
        echo "  Deleting images for $SERVICE..."
        if gcloud artifacts docker images delete "$IMAGE_PATH" --delete-tags --quiet 2>&1; then
            echo -e "  ${GREEN}Images deleted for $SERVICE${NC}"
        else
            echo -e "  ${YELLOW}Could not delete images for $SERVICE - may not exist${NC}"
        fi
    else
        echo -e "  ${YELLOW}No images found for $SERVICE - skipping${NC}"
    fi
done
echo ""

trap - SIGINT SIGTERM

echo -e "${BLUE}========================================${NC}"
echo -e "${GREEN}Cleanup complete!${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo "Cleanup attempted for:"
echo "  - Cloud Run services: gateway-service, user-service, order-service"
echo "  - VPC Connector: ${VPC_CONNECTOR_NAME}"
echo "  - Service account: ${SERVICE_ACCOUNT_NAME}"
echo "  - Container images from Artifact Registry"
echo ""
echo "To verify cleanup, run:"
echo "  gcloud run services list --region $REGION"
echo "  gcloud compute networks vpc-access connectors list --region $REGION"