#!/bin/bash

# Cloud Run Binary Authorization Demo - Sign and Deploy Script
# This script builds a container image, creates an attestation, and deploys to Cloud Run

set -e

echo "=================================="
echo "Build, Sign, and Deploy"
echo "=================================="
echo ""

# Load configuration
if [ ! -f config.env ]; then
  echo "Error: config.env not found. Please run ./01-setup.sh first."
  exit 1
fi

source config.env

SERVICE_NAME="binauthz-app"

# Authenticate to Artifact Registry
echo "1. Authenticating to Artifact Registry..."
gcloud auth configure-docker ${REGION}-docker.pkg.dev --quiet
echo "✓ Authenticated"
echo ""

# Build and push container image
echo "2. Building container image..."
echo "   This may take a few minutes..."
gcloud builds submit ./app \
  --tag=${IMAGE_URL}:latest \
  --quiet

echo "✓ Image built and pushed"
echo ""

# Get the image digest
echo "3. Getting image digest..."
IMAGE_DIGEST=$(gcloud artifacts docker images describe ${IMAGE_URL}:latest \
  --format='value(image_summary.digest)')

IMAGE_URL_WITH_DIGEST="${IMAGE_URL}@${IMAGE_DIGEST}"

echo "Image: ${IMAGE_URL_WITH_DIGEST}"
echo ""

# Create attestation
echo "4. Creating attestation (signing the image)..."
echo "   This cryptographically signs the container image..."

# The attestation proves that this specific image digest was verified
gcloud beta container binauthz attestations sign-and-create \
  --artifact-url="${IMAGE_URL_WITH_DIGEST}" \
  --attestor="${ATTESTOR_NAME}" \
  --attestor-project="${PROJECT_ID}" \
  --keyversion-project="${PROJECT_ID}" \
  --keyversion-location="${REGION}" \
  --keyversion-keyring="${KEYRING_NAME}" \
  --keyversion-key="${KEY_NAME}" \
  --keyversion="1" \
  --quiet

echo "✓ Attestation created"
echo ""

# Deploy to Cloud Run with Binary Authorization
echo "5. Deploying to Cloud Run..."
echo "   Binary Authorization will verify the attestation..."

gcloud run deploy ${SERVICE_NAME} \
  --image="${IMAGE_URL_WITH_DIGEST}" \
  --platform=managed \
  --region=${REGION} \
  --allow-unauthenticated \
  --binary-authorization=default \
  --quiet

echo "✓ Deployment successful!"
echo ""

# Get service URL
SERVICE_URL=$(gcloud run services describe ${SERVICE_NAME} \
  --region=${REGION} \
  --format='value(status.url)')

echo "=================================="
echo "Success!"
echo "=================================="
echo ""
echo "The signed container image was deployed to Cloud Run."
echo "Binary Authorization verified the attestation before allowing deployment."
echo ""
echo "Service URL: ${SERVICE_URL}"
echo ""
echo "Test the service:"
echo "  curl ${SERVICE_URL}"
echo ""
echo "View the service:"
echo "  ${SERVICE_URL}"
echo ""
