#!/bin/bash
# =============================================================================
# Cloud Run Service-to-Service Demo - Setup Script
# =============================================================================
# This script deploys three microservices to Cloud Run and configures
# service-to-service authentication using IAM with INTERNAL network traffic.
#
# Services:
#   - Gateway Service - Python - Public entry point
#   - User Service - Go - Internal service, can call Order Service
#   - Order Service - Node.js - Internal service
#
# Service Mesh Pattern:
#   Gateway -> User Service -> Order Service
#           -> Order Service
# =============================================================================

set -e

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
VPC_NETWORK="default"

# Service names
GATEWAY_SERVICE="gateway-service"
USER_SERVICE="user-service"
ORDER_SERVICE="order-service"

# Track deployment progress for cleanup on interrupt
DEPLOYED_SERVICES=""
VPC_CONNECTOR_CREATED=false
SERVICE_ACCOUNT_CREATED=false

# Cleanup function for Ctrl+C handling
cleanup_on_interrupt() {
    echo ""
    echo -e "${RED}========================================${NC}"
    echo -e "${RED}Setup interrupted! Cleaning up...${NC}"
    echo -e "${RED}========================================${NC}"
    echo ""
    
    # Delete any deployed services
    if [ -n "$DEPLOYED_SERVICES" ]; then
        for service in $DEPLOYED_SERVICES; do
            echo -e "${YELLOW}Deleting $service...${NC}"
            gcloud run services delete "$service" --region "$REGION" --quiet 2>/dev/null || true
        done
    fi
    
    echo ""
    echo -e "${YELLOW}Partial cleanup complete.${NC}"
    echo -e "${YELLOW}You may want to run 99-cleanup.sh to remove any remaining resources.${NC}"
    exit 1
}

# Set up trap for Ctrl+C and SIGTERM
trap cleanup_on_interrupt SIGINT SIGTERM

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Cloud Run Service-to-Service Demo${NC}"
echo -e "${BLUE}Service Mesh Pattern${NC}"
echo -e "${BLUE}========================================${NC}"
echo -e "${YELLOW}Press Ctrl+C at any time to cancel and cleanup${NC}"
echo ""

# Check prerequisites
echo -e "${YELLOW}Checking prerequisites...${NC}"

if [ -z "$PROJECT_ID" ]; then
    echo -e "${RED}Error: No GCP project configured.${NC}"
    echo "Run: gcloud config set project YOUR_PROJECT_ID"
    exit 1
fi

echo -e "  Project ID: ${GREEN}$PROJECT_ID${NC}"
echo -e "  Region: ${GREEN}$REGION${NC}"
echo ""

# Enable required APIs
echo -e "${YELLOW}Enabling required APIs...${NC}"
echo "  - cloudbuild.googleapis.com     - Cloud Build for container builds"
echo "  - run.googleapis.com            - Cloud Run for service deployment"
echo "  - artifactregistry.googleapis.com - Artifact Registry for container storage"
echo "  - iam.googleapis.com            - IAM for service account management"
echo "  - vpcaccess.googleapis.com      - VPC Access for internal networking"
echo "  - compute.googleapis.com        - Compute Engine for VPC resources"
echo ""

gcloud services enable \
    cloudbuild.googleapis.com \
    run.googleapis.com \
    artifactregistry.googleapis.com \
    iam.googleapis.com \
    vpcaccess.googleapis.com \
    compute.googleapis.com \
    --quiet

echo -e "${GREEN}APIs enabled${NC}"
echo ""

# Create VPC Connector for private networking
echo -e "${YELLOW}Setting up VPC Connector for internal communication...${NC}"

# Check if VPC connector exists and its status
CONNECTOR_STATUS=$(gcloud compute networks vpc-access connectors describe "$VPC_CONNECTOR_NAME" \
    --region "$REGION" \
    --format='value(state)' 2>/dev/null || echo "NOT_FOUND")

if [ "$CONNECTOR_STATUS" = "NOT_FOUND" ]; then
    echo "Creating VPC connector: $VPC_CONNECTOR_NAME"
    echo -e "${YELLOW}  This typically takes 2-3 minutes, please wait...${NC}"
    
    # Create connector with async and then wait
    gcloud compute networks vpc-access connectors create "$VPC_CONNECTOR_NAME" \
        --region "$REGION" \
        --network "$VPC_NETWORK" \
        --range "10.8.0.0/28" \
        --min-instances 2 \
        --max-instances 3 \
        --async \
        --quiet
    
    # Wait for the connector to be ready with progress indicator
    echo -n "  Waiting for VPC connector to be ready"
    while true; do
        STATUS=$(gcloud compute networks vpc-access connectors describe "$VPC_CONNECTOR_NAME" \
            --region "$REGION" \
            --format='value(state)' 2>/dev/null || echo "CREATING")
        
        if [ "$STATUS" = "READY" ]; then
            echo ""
            break
        elif [ "$STATUS" = "ERROR" ]; then
            echo ""
            echo -e "${RED}Error: VPC connector creation failed${NC}"
            exit 1
        fi
        
        echo -n "."
        sleep 5
    done
    
    VPC_CONNECTOR_CREATED=true
    echo -e "${GREEN}VPC connector created and ready${NC}"
elif [ "$CONNECTOR_STATUS" = "READY" ]; then
    echo -e "${GREEN}VPC connector already exists and is READY${NC}"
else
    echo -e "${YELLOW}VPC connector exists but status is $CONNECTOR_STATUS. Waiting for READY...${NC}"
    # Wait for the connector to be ready
    echo -n "  Waiting for VPC connector to be ready"
    while true; do
        STATUS=$(gcloud compute networks vpc-access connectors describe "$VPC_CONNECTOR_NAME" \
            --region "$REGION" \
            --format='value(state)' 2>/dev/null || echo "UNKNOWN")
        
        if [ "$STATUS" = "READY" ]; then
            echo ""
            break
        elif [ "$STATUS" = "ERROR" ]; then
            echo ""
            echo -e "${RED}Error: VPC connector is in ERROR state. Please delete it manually and retry.${NC}"
            exit 1
        fi
        
        echo -n "."
        sleep 5
    done
    echo -e "${GREEN}VPC connector is READY${NC}"
fi
echo ""

# Create service account for service-to-service authentication
echo -e "${YELLOW}Setting up service account for S2S authentication...${NC}"
SERVICE_ACCOUNT_EMAIL="${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

if ! gcloud iam service-accounts describe "$SERVICE_ACCOUNT_EMAIL" &>/dev/null; then
    echo "Creating service account: $SERVICE_ACCOUNT_NAME"
    gcloud iam service-accounts create "$SERVICE_ACCOUNT_NAME" \
        --display-name="Cloud Run Service-to-Service Invoker" \
        --description="Service account for Cloud Run service-to-service authentication"
    SERVICE_ACCOUNT_CREATED=true
    echo -e "${GREEN}Service account created${NC}"
else
    echo -e "${GREEN}Service account already exists${NC}"
fi
echo ""

# =============================================================================
# Deploy Order Service - Node.js - Internal Only
# Deploy this FIRST because User Service needs its URL
# =============================================================================
echo -e "${BLUE}----------------------------------------${NC}"
echo -e "${BLUE}Deploying Order Service - Node.js${NC}"
echo -e "${BLUE}----------------------------------------${NC}"
echo -e "${YELLOW}  Building and deploying, this may take 1-2 minutes...${NC}"

cd order-service

gcloud run deploy "$ORDER_SERVICE" \
    --source . \
    --region "$REGION" \
    --platform managed \
    --no-allow-unauthenticated \
    --ingress internal \
    --memory 256Mi \
    --cpu 1 \
    --min-instances 0 \
    --max-instances 3 \
    --timeout 60 \
    --quiet

DEPLOYED_SERVICES="$DEPLOYED_SERVICES $ORDER_SERVICE"

# Get the service URL
ORDER_SERVICE_URL=$(gcloud run services describe "$ORDER_SERVICE" \
    --region "$REGION" \
    --format 'value(status.url)')

echo -e "${GREEN}Order Service deployed: $ORDER_SERVICE_URL${NC}"
echo -e "${GREEN}  Ingress: INTERNAL - not accessible from internet${NC}"

# Grant the invoker service account permission to call this service
echo "Granting invoke permission to service account..."
gcloud run services add-iam-policy-binding "$ORDER_SERVICE" \
    --region "$REGION" \
    --member "serviceAccount:${SERVICE_ACCOUNT_EMAIL}" \
    --role "roles/run.invoker" \
    --quiet

echo -e "${GREEN}IAM policy configured${NC}"
cd ..
echo ""

# =============================================================================
# Deploy User Service - Go - Internal Only
# User Service can call Order Service - service mesh pattern
# =============================================================================
echo -e "${BLUE}----------------------------------------${NC}"
echo -e "${BLUE}Deploying User Service - Go${NC}"
echo -e "${BLUE}----------------------------------------${NC}"
echo -e "${YELLOW}  Building and deploying, this may take 1-2 minutes...${NC}"
echo -e "${YELLOW}  Note: User Service will be able to call Order Service${NC}"

cd user-service

# User Service needs:
# 1. To accept internal traffic only
# 2. To be able to call Order Service via VPC
# 3. To use the service account for OIDC authentication
gcloud run deploy "$USER_SERVICE" \
    --source . \
    --region "$REGION" \
    --platform managed \
    --no-allow-unauthenticated \
    --ingress internal \
    --service-account "$SERVICE_ACCOUNT_EMAIL" \
    --vpc-connector "$VPC_CONNECTOR_NAME" \
    --vpc-egress all-traffic \
    --memory 256Mi \
    --cpu 1 \
    --min-instances 0 \
    --max-instances 3 \
    --timeout 60 \
    --set-env-vars "ORDER_SERVICE_URL=${ORDER_SERVICE_URL}" \
    --quiet

DEPLOYED_SERVICES="$DEPLOYED_SERVICES $USER_SERVICE"

# Get the service URL
USER_SERVICE_URL=$(gcloud run services describe "$USER_SERVICE" \
    --region "$REGION" \
    --format 'value(status.url)')

echo -e "${GREEN}User Service deployed: $USER_SERVICE_URL${NC}"
echo -e "${GREEN}  Ingress: INTERNAL - not accessible from internet${NC}"
echo -e "${GREEN}  Can call: Order Service via VPC${NC}"

# Grant the invoker service account permission to call this service
echo "Granting invoke permission to service account..."
gcloud run services add-iam-policy-binding "$USER_SERVICE" \
    --region "$REGION" \
    --member "serviceAccount:${SERVICE_ACCOUNT_EMAIL}" \
    --role "roles/run.invoker" \
    --quiet

echo -e "${GREEN}IAM policy configured${NC}"
cd ..
echo ""

# =============================================================================
# Deploy Gateway Service - Python - Public with VPC Connector
# =============================================================================
echo -e "${BLUE}----------------------------------------${NC}"
echo -e "${BLUE}Deploying Gateway Service - Python${NC}"
echo -e "${BLUE}----------------------------------------${NC}"
echo -e "${YELLOW}  Building and deploying, this may take 1-2 minutes...${NC}"

cd gateway-service

# The gateway uses the invoker service account and VPC connector to call other services
gcloud run deploy "$GATEWAY_SERVICE" \
    --source . \
    --region "$REGION" \
    --platform managed \
    --allow-unauthenticated \
    --ingress all \
    --service-account "$SERVICE_ACCOUNT_EMAIL" \
    --vpc-connector "$VPC_CONNECTOR_NAME" \
    --vpc-egress all-traffic \
    --memory 512Mi \
    --cpu 1 \
    --min-instances 0 \
    --max-instances 5 \
    --timeout 120 \
    --set-env-vars "USER_SERVICE_URL=${USER_SERVICE_URL},ORDER_SERVICE_URL=${ORDER_SERVICE_URL}" \
    --quiet

DEPLOYED_SERVICES="$DEPLOYED_SERVICES $GATEWAY_SERVICE"

# Get the service URL
GATEWAY_SERVICE_URL=$(gcloud run services describe "$GATEWAY_SERVICE" \
    --region "$REGION" \
    --format 'value(status.url)')

echo -e "${GREEN}Gateway Service deployed: $GATEWAY_SERVICE_URL${NC}"
echo -e "${GREEN}  Ingress: ALL - publicly accessible${NC}"
echo -e "${GREEN}  Egress: Via VPC Connector - internal network${NC}"
cd ..
echo ""

# Remove trap after successful completion
trap - SIGINT SIGTERM

# =============================================================================
# Summary
# =============================================================================
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Deployment Complete!${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo -e "${GREEN}Service URLs:${NC}"
echo "  Gateway - Python:   ${GATEWAY_SERVICE_URL}"
echo "  User - Go:          ${USER_SERVICE_URL} - internal only"
echo "  Order - Node.js:    ${ORDER_SERVICE_URL} - internal only"
echo ""
echo -e "${GREEN}Service Mesh Configuration:${NC}"
echo "  Gateway  -> User Service  - via VPC + OIDC"
echo "  Gateway  -> Order Service - via VPC + OIDC"
echo "  User Service -> Order Service - via VPC + OIDC"
echo ""
echo -e "${GREEN}Network Configuration:${NC}"
echo "  VPC Connector:      ${VPC_CONNECTOR_NAME}"
echo "  Gateway Ingress:    ALL - public"
echo "  Gateway Egress:     VPC - internal network"
echo "  User Ingress:       INTERNAL"
echo "  User Egress:        VPC - can call Order Service"
echo "  Order Ingress:      INTERNAL"
echo ""
echo -e "${GREEN}Authentication - OIDC:${NC}"
echo "  Service Account:    ${SERVICE_ACCOUNT_EMAIL}"
echo "  All services use OIDC ID tokens for authenticated calls"
echo ""
echo -e "${YELLOW}Communication Flows:${NC}"
echo ""
echo "  Client --> Gateway ----> User Service ----> Order Service"
echo "                  |                                 ^"
echo "                  +---------------------------------+"
echo ""
echo "  All internal traffic uses VPC + OIDC authentication"
echo ""
echo -e "${YELLOW}Test the deployment:${NC}"
echo ""
echo "  # Health check"
echo "  curl ${GATEWAY_SERVICE_URL}/"
echo ""
echo "  # Get users and their orders - Gateway -> User -> Order"
echo "  curl ${GATEWAY_SERVICE_URL}/api/user-orders/user-001"
echo ""
echo "  # User Service directly fetching orders - User -> Order"
echo "  curl ${GATEWAY_SERVICE_URL}/api/users/user-001"
echo ""
echo -e "${GREEN}Or run: ./02-test.sh${NC}"