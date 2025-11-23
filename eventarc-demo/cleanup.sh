#!/bin/bash

# Eventarc Demo - Cleanup Script
# This script removes all resources created by the setup script

set -e

echo "=================================="
echo "Eventarc Demo - Cleanup"
echo "=================================="
echo ""

# Load configuration
if [ -f config.env ]; then
  source config.env
else
  echo "Warning: config.env not found. Using default values."
  PROJECT_ID=$(gcloud config get-value project)
  REGION="us-central1"
  SERVICE_NAME="eventarc-demo-service"
  TRIGGER_NAME="storage-event-trigger"
  BUCKET_NAME=""
fi

echo "Project ID: $PROJECT_ID"
echo "Region: $REGION"
echo ""

# Delete Eventarc trigger
echo "1. Deleting Eventarc trigger..."
if gcloud eventarc triggers describe ${TRIGGER_NAME} --location=${REGION} --quiet 2>/dev/null; then
  gcloud eventarc triggers delete ${TRIGGER_NAME} --location=${REGION} --quiet
  echo "✓ Trigger deleted"
else
  echo "Trigger not found, skipping"
fi
echo ""

# Delete Cloud Run service
echo "2. Deleting Cloud Run service..."
if gcloud run services describe ${SERVICE_NAME} --region=${REGION} --quiet 2>/dev/null; then
  gcloud run services delete ${SERVICE_NAME} --region=${REGION} --quiet
  echo "✓ Cloud Run service deleted"
else
  echo "Service not found, skipping"
fi
echo ""

# Delete Cloud Storage bucket
echo "3. Deleting Cloud Storage bucket..."
if [ -n "$BUCKET_NAME" ] && gsutil ls gs://${BUCKET_NAME} 2>/dev/null; then
  echo "  Removing bucket (this will delete all objects)..."
  gsutil -m rb -f gs://${BUCKET_NAME}
  echo "✓ Bucket deleted"
else
  echo "Bucket not found or bucket name not set, skipping"
fi
echo ""

# Remove config file
echo "4. Removing configuration file..."
if [ -f config.env ]; then
  rm config.env
  echo "✓ config.env removed"
fi
echo ""

echo "=================================="
echo "Cleanup Complete!"
echo "=================================="
echo ""
echo "All resources have been removed."
echo ""
echo "Note: IAM policy bindings may persist. To review:"
echo "  gcloud projects get-iam-policy $PROJECT_ID"
