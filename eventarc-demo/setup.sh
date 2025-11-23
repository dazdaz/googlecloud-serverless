#!/bin/bash

# Eventarc Demo - Setup Script
# This script creates a Cloud Storage bucket, Cloud Run service, and Eventarc trigger

set -e

# Track created resources for cleanup
CREATED_BUCKET=""
CREATED_SERVICE=""
CREATED_TRIGGER=""

# Cleanup function
cleanup_on_error() {
  local exit_code=$?
  if [ $exit_code -ne 0 ]; then
    echo ""
    echo "=================================="
    echo "Setup interrupted or failed!"
    echo "Cleaning up partially created resources..."
    echo "=================================="
    
    # Remove trigger if created
    if [ ! -z "$CREATED_TRIGGER" ]; then
      echo "Removing Eventarc trigger: $CREATED_TRIGGER"
      gcloud eventarc triggers delete $CREATED_TRIGGER \
        --location=$REGION \
        --quiet 2>/dev/null || true
    fi
    
    # Remove Cloud Run service if created
    if [ ! -z "$CREATED_SERVICE" ]; then
      echo "Removing Cloud Run service: $CREATED_SERVICE"
      gcloud run services delete $CREATED_SERVICE \
        --region=$REGION \
        --quiet 2>/dev/null || true
    fi
    
    # Remove bucket if created
    if [ ! -z "$CREATED_BUCKET" ]; then
      echo "Removing Cloud Storage bucket: $CREATED_BUCKET"
      gsutil rm -r $CREATED_BUCKET 2>/dev/null || true
    fi
    
    echo ""
    echo "Cleanup complete. You can re-run setup.sh to try again."
  fi
}

# Set up trap to catch errors and interrupts
trap cleanup_on_error EXIT INT TERM

echo "=================================="
echo "Eventarc Demo - Setup"
echo "=================================="
echo ""

# Configuration
PROJECT_ID=$(gcloud config get-value project)
PROJECT_NUMBER=$(gcloud projects describe $PROJECT_ID --format='value(projectNumber)')
REGION="us-central1"
SERVICE_NAME="eventarc-demo-service"
BUCKET_NAME="${PROJECT_ID}-eventarc-demo-${RANDOM}"
TRIGGER_NAME="storage-event-trigger"

echo "Project ID: $PROJECT_ID"
echo "Project Number: $PROJECT_NUMBER"
echo "Region: $REGION"
echo "Bucket Name: $BUCKET_NAME"
echo ""

# Enable required APIs
echo "1. Enabling required APIs..."
gcloud services enable \
  eventarc.googleapis.com \
  run.googleapis.com \
  storage.googleapis.com \
  cloudbuild.googleapis.com \
  pubsub.googleapis.com \
  --quiet

echo "✓ APIs enabled"
echo ""
echo "   Waiting 30 seconds for Eventarc service agent to be provisioned..."
sleep 30
echo "   ✓ Service agent provisioning time elapsed"
echo ""

# Create Cloud Storage bucket
echo "2. Creating Cloud Storage bucket..."
gsutil mb -l ${REGION} gs://${BUCKET_NAME}
CREATED_BUCKET="gs://${BUCKET_NAME}"
echo "✓ Bucket created: gs://${BUCKET_NAME}"
echo ""

# Build and deploy Cloud Run service
echo "3. Building and deploying Cloud Run service..."
echo "   (This may take a few minutes...)"
gcloud run deploy ${SERVICE_NAME} \
  --source=./service \
  --region=${REGION} \
  --platform=managed \
  --allow-unauthenticated \
  --quiet

CREATED_SERVICE="${SERVICE_NAME}"
echo "✓ Cloud Run service deployed"
echo ""

# Get service URL
SERVICE_URL=$(gcloud run services describe ${SERVICE_NAME} \
  --region=${REGION} \
  --format='value(status.url)')

echo "Service URL: $SERVICE_URL"
echo ""

# Create Eventarc trigger for Cloud Storage events
# This will automatically create the Eventarc service account and set up permissions
echo "4. Setting up IAM permissions for Eventarc..."

# Grant Cloud Storage service agent permission to publish to Pub/Sub
GCS_SA="service-${PROJECT_NUMBER}@gs-project-accounts.iam.gserviceaccount.com"
gcloud projects add-iam-policy-binding ${PROJECT_ID} \
  --member="serviceAccount:${GCS_SA}" \
  --role="roles/pubsub.publisher" \
  --quiet 2>/dev/null || echo "Note: GCS service agent already has pubsub.publisher role"

echo "✓ Cloud Storage service agent configured"
echo ""

echo "5. Creating Eventarc trigger..."
echo "   (This may take a few minutes...)"
echo "   Note: This will automatically create the Eventarc service account and configure permissions"
echo ""

# Grant the default Compute Engine service account permission to invoke the service
# This is needed for Eventarc to work properly
COMPUTE_SA="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"
gcloud run services add-iam-policy-binding ${SERVICE_NAME} \
  --member="serviceAccount:${COMPUTE_SA}" \
  --role="roles/run.invoker" \
  --region=${REGION} \
  --quiet 2>/dev/null || echo "Note: Compute service account permission already exists or not needed"

# Create the trigger - this will create the Eventarc service account automatically
gcloud eventarc triggers create ${TRIGGER_NAME} \
  --location=${REGION} \
  --destination-run-service=${SERVICE_NAME} \
  --destination-run-region=${REGION} \
  --event-filters="type=google.cloud.storage.object.v1.finalized" \
  --event-filters="bucket=${BUCKET_NAME}" \
  --service-account="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"

CREATED_TRIGGER="${TRIGGER_NAME}"
echo "✓ Eventarc trigger created"
echo ""

# Now grant permissions to the Eventarc service account (created by the trigger)
echo "6. Configuring final IAM permissions..."
EVENTARC_SA="service-${PROJECT_NUMBER}@gcp-sa-eventarc.iam.gserviceaccount.com"

# Grant eventarc.eventReceiver role to invoke Cloud Run
gcloud run services add-iam-policy-binding ${SERVICE_NAME} \
  --member="serviceAccount:${EVENTARC_SA}" \
  --role="roles/run.invoker" \
  --region=${REGION} \
  --quiet 2>/dev/null || echo "Note: Eventarc service account already has invoker permission"

echo "✓ IAM permissions configured"
echo ""

# Store configuration for other scripts
cat > config.env << EOF
export PROJECT_ID="${PROJECT_ID}"
export REGION="${REGION}"
export BUCKET_NAME="${BUCKET_NAME}"
export SERVICE_NAME="${SERVICE_NAME}"
export TRIGGER_NAME="${TRIGGER_NAME}"
EOF

# Disable trap on successful completion
trap - EXIT INT TERM

echo "=================================="
echo "Setup Complete!"
echo "=================================="
echo ""
echo "Resources created:"
echo "- Storage Bucket: gs://${BUCKET_NAME}"
echo "- Cloud Run Service: ${SERVICE_NAME}"
echo "- Eventarc Trigger: ${TRIGGER_NAME}"
echo ""
echo "Trigger Configuration:"
gcloud eventarc triggers describe ${TRIGGER_NAME} --location=${REGION}
echo ""
echo "Next steps:"
echo "1. Run './trigger.sh' to upload a test file"
echo "2. Upload files: gsutil cp yourfile.txt gs://${BUCKET_NAME}/"
echo "3. View logs: gcloud run services logs read ${SERVICE_NAME} --region=${REGION} --limit=20"
echo ""
