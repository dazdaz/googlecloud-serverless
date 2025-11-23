#!/bin/bash

# Cloud Run Binary Authorization Demo - Setup Script
# This script sets up Binary Authorization for Cloud Run with attestors and KMS signing

set -e

# Track created resources for cleanup
CREATED_REPO=""
CREATED_KEYRING=""
CREATED_KEY=""
CREATED_SERVICE_ACCOUNT=""
CREATED_ATTESTOR=""
POLICY_MODIFIED=false

# Cleanup function
cleanup_on_error() {
  local exit_code=$?
  if [ $exit_code -ne 0 ]; then
    echo ""
    echo "=================================="
    echo "Setup interrupted or failed!"
    echo "Cleaning up partially created resources..."
    echo "=================================="
    
    # Reset Binary Authorization policy
    if [ "$POLICY_MODIFIED" = true ]; then
      echo "Resetting Binary Authorization policy to default..."
      cat > /tmp/reset-policy.yaml << EOF
admissionWhitelistPatterns:
- namePattern: "*"
defaultAdmissionRule:
  evaluationMode: ALWAYS_ALLOW
  enforcementMode: ENFORCED_BLOCK_AND_AUDIT_LOG
name: projects/${PROJECT_ID}/policy
EOF
      gcloud container binauthz policy import /tmp/reset-policy.yaml --quiet 2>/dev/null || true
      rm -f /tmp/reset-policy.yaml
    fi
    
    # Remove attestor
    if [ ! -z "$CREATED_ATTESTOR" ]; then
      echo "Removing attestor: $CREATED_ATTESTOR"
      gcloud container binauthz attestors delete $CREATED_ATTESTOR --quiet 2>/dev/null || true
    fi
    
    # Remove service account
    if [ ! -z "$CREATED_SERVICE_ACCOUNT" ]; then
      echo "Removing service account: $CREATED_SERVICE_ACCOUNT"
      gcloud iam service-accounts delete $CREATED_SERVICE_ACCOUNT --quiet 2>/dev/null || true
    fi
    
    # Note: KMS keys cannot be deleted immediately, only scheduled for deletion
    # Note: Artifact Registry repositories are left for manual cleanup
    
    echo ""
    echo "Cleanup complete. You can re-run setup.sh to try again."
    echo "Note: KMS keys are scheduled for deletion (30-day waiting period)"
  fi
}

# Set up trap to catch errors and interrupts
trap cleanup_on_error EXIT INT TERM

echo "=================================="
echo "Binary Authorization Demo - Setup"
echo "=================================="
echo ""

# Configuration
PROJECT_ID=$(gcloud config get-value project)
REGION="us-central1"
REPO_NAME="binauthz-demo"
ATTESTOR_NAME="binauthz-attestor"
KEYRING_NAME="binauthz-keyring"
KEY_NAME="binauthz-key"
SERVICE_ACCOUNT_NAME="binauthz-signer"

echo "Project ID: $PROJECT_ID"
echo "Region: $REGION"
echo ""

# Enable required APIs
echo "1. Enabling required APIs..."
gcloud services enable \
  binaryauthorization.googleapis.com \
  containeranalysis.googleapis.com \
  run.googleapis.com \
  cloudbuild.googleapis.com \
  artifactregistry.googleapis.com \
  cloudkms.googleapis.com \
  --quiet

echo "✓ APIs enabled"
echo ""

# Create Artifact Registry repository
echo "2. Creating Artifact Registry repository..."
if gcloud artifacts repositories describe ${REPO_NAME} --location=${REGION} --quiet 2>/dev/null; then
  echo "Repository already exists, skipping creation"
else
  gcloud artifacts repositories create ${REPO_NAME} \
    --repository-format=docker \
    --location=${REGION} \
    --description="Binary Authorization demo repository" \
    --quiet
  CREATED_REPO="${REPO_NAME}"
  echo "✓ Artifact Registry repository created"
fi
echo ""

# Create KMS keyring and key for signing
echo "3. Creating KMS keyring and key for attestation signing..."
if gcloud kms keyrings describe ${KEYRING_NAME} --location=${REGION} --quiet 2>/dev/null; then
  echo "Keyring already exists"
else
  gcloud kms keyrings create ${KEYRING_NAME} --location=${REGION} --quiet
  CREATED_KEYRING="${KEYRING_NAME}"
  echo "✓ Keyring created"
fi

if gcloud kms keys describe ${KEY_NAME} --keyring=${KEYRING_NAME} --location=${REGION} --quiet 2>/dev/null; then
  echo "Key already exists"
else
  gcloud kms keys create ${KEY_NAME} \
    --keyring=${KEYRING_NAME} \
    --location=${REGION} \
    --purpose=asymmetric-signing \
    --default-algorithm=rsa-sign-pkcs1-4096-sha512 \
    --quiet
  CREATED_KEY="${KEY_NAME}"
  echo "✓ KMS key created"
fi
echo ""

# Create service account for attestation signing
echo "4. Creating service account for attestation signing..."
if gcloud iam service-accounts describe ${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com --quiet 2>/dev/null; then
  echo "Service account already exists"
else
  gcloud iam service-accounts create ${SERVICE_ACCOUNT_NAME} \
    --display-name="Binary Authorization Signer" \
    --quiet
  CREATED_SERVICE_ACCOUNT="${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
  echo "✓ Service account created"
fi
echo ""

# Grant IAM permissions
echo "5. Configuring IAM permissions..."

# Grant KMS signing permission to service account
gcloud kms keys add-iam-policy-binding ${KEY_NAME} \
  --keyring=${KEYRING_NAME} \
  --location=${REGION} \
  --member="serviceAccount:${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" \
  --role=roles/cloudkms.signerVerifier \
  --quiet

# Grant Container Analysis Occurrences Editor to service account
gcloud projects add-iam-policy-binding ${PROJECT_ID} \
  --member="serviceAccount:${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" \
  --role=roles/containeranalysis.occurrences.editor \
  --quiet

echo "✓ IAM permissions configured"
echo ""

# Create attestor
echo "6. Creating Binary Authorization attestor..."
if gcloud container binauthz attestors describe ${ATTESTOR_NAME} --quiet 2>/dev/null; then
  echo "Attestor already exists"
else
  # Get the KMS key version resource name
  KEY_VERSION=$(gcloud kms keys versions describe 1 \
    --key=${KEY_NAME} \
    --keyring=${KEYRING_NAME} \
    --location=${REGION} \
    --format='value(name)')
  
  # Create the attestor
  gcloud container binauthz attestors create ${ATTESTOR_NAME} \
    --attestation-authority-note=projects/${PROJECT_ID}/notes/${ATTESTOR_NAME} \
    --attestation-authority-note-project=${PROJECT_ID} \
    --quiet
  
  # Add the public key from KMS
  gcloud container binauthz attestors public-keys add \
    --attestor=${ATTESTOR_NAME} \
    --keyversion-project=${PROJECT_ID} \
    --keyversion-location=${REGION} \
    --keyversion-keyring=${KEYRING_NAME} \
    --keyversion-key=${KEY_NAME} \
    --keyversion=1 \
    --quiet
  
  CREATED_ATTESTOR="${ATTESTOR_NAME}"
  echo "✓ Attestor created"
fi
echo ""

# Configure Binary Authorization policy
echo "7. Configuring Binary Authorization policy..."

# Create policy that requires attestation
cat > /tmp/binauthz-policy.yaml << EOF
admissionWhitelistPatterns:
- namePattern: gcr.io/google-containers/*
- namePattern: gcr.io/google.com/*
- namePattern: k8s.gcr.io/*
defaultAdmissionRule:
  requireAttestationsBy:
  - projects/${PROJECT_ID}/attestors/${ATTESTOR_NAME}
  evaluationMode: REQUIRE_ATTESTATION
  enforcementMode: ENFORCED_BLOCK_AND_AUDIT_LOG
name: projects/${PROJECT_ID}/policy
EOF

gcloud container binauthz policy import /tmp/binauthz-policy.yaml --quiet
POLICY_MODIFIED=true
rm /tmp/binauthz-policy.yaml

echo "✓ Binary Authorization policy configured"
echo ""

# Save configuration for other scripts
cat > config.env << EOF
export PROJECT_ID="${PROJECT_ID}"
export REGION="${REGION}"
export REPO_NAME="${REPO_NAME}"
export ATTESTOR_NAME="${ATTESTOR_NAME}"
export KEYRING_NAME="${KEYRING_NAME}"
export KEY_NAME="${KEY_NAME}"
export SERVICE_ACCOUNT_NAME="${SERVICE_ACCOUNT_NAME}"
export IMAGE_URL="${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPO_NAME}/binauthz-app"
EOF

echo "Configuration saved to config.env"
echo ""

# Disable trap on successful completion
trap - EXIT INT TERM

echo "=================================="
echo "Setup Complete!"
echo "=================================="
echo ""
echo "Binary Authorization is now configured for Cloud Run."
echo ""
echo "Resources created:"
echo "- Artifact Registry: ${REPO_NAME}"
echo "- KMS Keyring: ${KEYRING_NAME}"
echo "- KMS Key: ${KEY_NAME}"
echo "- Service Account: ${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
echo "- Attestor: ${ATTESTOR_NAME}"
echo "- Policy: Requires attestation for all images"
echo ""
echo "Next steps:"
echo "1. Run './sign-and-deploy.sh' to build, sign, and deploy a verified image"
echo "2. Run './test-unsigned.sh' to test blocking of unsigned images"
echo ""
