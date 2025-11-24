# Cloud Run Binary Authorization Demo

This demo shows how to use **Binary Authorization** to ensure that only cryptographically signed and verified container images can be deployed to Cloud Run.

## 📋 Overview

Binary Authorization is a deploy-time security control that ensures only trusted container images are deployed to your Cloud Run services. It works by:

1. **Requiring cryptographic attestations** (signatures) on container images
2. **Verifying attestations** before allowing deployment
3. **Blocking unsigned or untrusted images** automatically

## 🎯 What This Demo Demonstrates

- **Setup**: Configure Binary Authorization with policies, attestors, and KMS signing
- **Build & Sign**: Build a container image and create cryptographic attestations
- **Deploy Signed**: Deploy a signed image to Cloud Run (✅ succeeds)
- **Block Unsigned**: Attempt to deploy unsigned image (❌ blocked by policy)
- **Cleanup**: Remove all created resources

## 🏗️ Architecture

```
┌─────────────────┐
│  Cloud Build    │──► Build container image
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Artifact        │──► Store container image
│ Registry        │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Create          │──► Sign image with KMS key
│ Attestation     │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Binary Auth     │──► Verify attestation
│ Policy Check    │
└────────┬────────┘
         │
    ✅ Signed │ ❌ Unsigned
         │
         ▼
┌─────────────────┐
│  Cloud Run      │──► Deploy (or block)
└─────────────────┘
```

## 🚀 Quick Start

### Prerequisites

```bash
# Set your project
export PROJECT_ID="your-project-id"
gcloud config set project $PROJECT_ID

# Set region
export REGION=us-central1
```

### 1. Setup Binary Authorization

Creates all necessary resources: Artifact Registry, KMS keys, attestors, and policy.

```bash
./01-setup.sh
```

**Creates:**
- Artifact Registry repository
- KMS keyring and signing key
- Service account for signing
- Binary Authorization attestor
- Policy requiring attestations

### 2. Build, Sign, and Deploy

Builds a container image, creates an attestation, and deploys to Cloud Run.

```bash
./02-sign-and-deploy.sh
```

**Steps:**
1. Builds container image with Cloud Build
2. Pushes to Artifact Registry
3. Gets image digest
4. Creates cryptographic attestation using KMS
5. Deploys to Cloud Run (succeeds because image is signed)

### 3. Test Unsigned Deployment

Demonstrates security by attempting to deploy an unsigned image.

```bash
./03-test-unsigned.sh
```

**Expected result:** Deployment is **blocked** by Binary Authorization

### 4. Cleanup

Removes all resources created by the demo.

```bash
./99-cleanup.sh
```

## 📦 Components

### Application (`app/`)

Simple Flask web application that returns a success message when deployed.

- **main.py** - Flask application
- **requirements.txt** - Python dependencies
- **Dockerfile** - Container image definition

### Scripts

- **01-setup.sh** - Creates all Binary Authorization resources
- **02-sign-and-deploy.sh** - Builds, signs, and deploys container
- **03-test-unsigned.sh** - Tests blocking of unsigned images
- **99-cleanup.sh** - Removes all resources

## 🔐 How Binary Authorization Works

### 1. Attestation Creation

When you sign an image, Binary Authorization:
1. Takes the container image digest (SHA256 hash)
2. Creates a cryptographic signature using your KMS key
3. Stores the attestation in Container Analysis

```bash
gcloud beta container binauthz attestations sign-and-create \
  --artifact-url="image@digest" \
  --attestor="attestor-name" \
  --keyversion="key-version"
```

### 2. Policy Enforcement

Before deploying to Cloud Run, Binary Authorization:
1. Checks if the image has a required attestation
2. Verifies the attestation signature with KMS
3. Allows deployment only if valid attestation exists

### 3. Security Benefits

✅ **Prevent unauthorized deployments** - Only signed images can be deployed  
✅ **Cryptographic verification** - Signatures can't be forged  
✅ **Audit trail** - All deployments are logged  
✅ **Supply chain security** - Verify image provenance  

## 🔧 Configuration

### Binary Authorization Policy

The policy (`setup.sh` line 159) requires attestations:

```yaml
defaultAdmissionRule:
  requireAttestationsBy:
  - projects/${PROJECT_ID}/attestors/${ATTESTOR_NAME}
  enforcementMode: ENFORCED_BLOCK_AND_AUDIT_LOG
```

### Allowlist Patterns

Some Google images are allowed without attestation:

```yaml
admissionWhitelistPatterns:
- namePattern: gcr.io/google-containers/*
- namePattern: gcr.io/google.com/*
```

## 🎓 Learning Outcomes

After completing this demo, you'll understand:

1. **Binary Authorization basics** - What it is and why it matters
2. **Attestation process** - How to sign container images
3. **Policy enforcement** - How to configure and test policies
4. **Cloud Run integration** - How BinAuthz works with Cloud Run
5. **Security best practices** - Protecting your deployments

## 📊 Expected Output

### Successful Signed Deployment

```
5. Deploying to Cloud Run...
   Binary Authorization will verify the attestation...
✓ Deployment successful!

The signed container image was deployed to Cloud Run.
Binary Authorization verified the attestation before allowing deployment.

Service URL: https://binauthz-app-xxxxx-uc.a.run.app
```

### Blocked Unsigned Deployment

```
4. Attempting to deploy unsigned image to Cloud Run...
   Binary Authorization should BLOCK this deployment...

ERROR: (gcloud.run.deploy) Image does not have required attestations

✅ SUCCESS: Deployment was BLOCKED!

Binary Authorization successfully prevented the deployment of an unsigned image.
```

## 🔍 Troubleshooting

### Deployment Still Blocked After Signing

**Issue:** Signed image deployment fails  
**Solution:** 
```bash
# Verify attestation exists
gcloud container binauthz attestations list \
  --artifact-url="image@digest" \
  --attestor="binauthz-attestor"

# Check policy
gcloud container binauthz policy export
```

### KMS Permission Errors

**Issue:** Cannot create attestation  
**Solution:**
```bash
# Verify service account has KMS signer role
gcloud kms keys get-iam-policy binauthz-key \
  --keyring=binauthz-keyring \
  --location=us-central1
```

### Unsigned Image Allowed

**Issue:** Unsigned image deployed successfully  
**Solution:** Check that Binary Authorization is enabled and policy is correct:
```bash
gcloud container binauthz policy export

# Ensure defaultAdmissionRule requires attestations
# and enforcementMode is ENFORCED_BLOCK_AND_AUDIT_LOG
```

## 💰 Cost Considerations

**Services used:**
- Cloud Run (pay per use)
- Cloud Build (first 120 build-minutes/day free)
- Artifact Registry (0.5GB free per month)
- Cloud KMS (keys $0.06/month, operations $0.03/10,000)
- Container Analysis (storage only)

**Estimated cost for demo:** < $1 if cleaned up promptly

## 🔗 Resources

### Official Documentation

- [Binary Authorization Overview](https://cloud.google.com/binary-authorization/docs/overview)
- [Using Binary Authorization with Cloud Run](https://cloud.google.com/run/docs/securing/binary-authorization)
- [Creating Attestations](https://docs.cloud.google.com/binary-authorization/docs/making-attestations)
- [Policy Reference](https://cloud.google.com/binary-authorization/docs/policy-yaml-reference)

### Related Topics

- [Cloud KMS](https://cloud.google.com/kms/docs)
- [Artifact Registry](https://cloud.google.com/artifact-registry/docs)
- [Container Analysis](https://cloud.google.com/container-analysis/docs)
- [Supply Chain Security](https://cloud.google.com/software-supply-chain-security)

## 📝 Notes

- **KMS keys** cannot be immediately deleted; they have a 30-day deletion grace period
- **Attestations** are stored in Container Analysis and tied to specific image digests
- **Policies** apply project-wide; use allowlist patterns for exceptions
- **Image tags** (like `:latest`) are not allowed; must use digests (`@sha256:...`)

## 🤝 Contributing

This demo is part of the [gcp-serverless](../) repository. Issues and pull requests welcome!

---

**Security Note:** This demo uses Binary Authorization with KMS-based signing to demonstrate enterprise-grade container image security for Cloud Run deployments.
