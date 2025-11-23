# GCP Task & Workflow Orchestration Demos

A comprehensive guide to **4 GCP services** for task scheduling, event processing, and workflow orchestration with hands-on demos.

[![GCP](https://img.shields.io/badge/Google%20Cloud-4285F4?logo=google-cloud&logoColor=white)](https://cloud.google.com)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

---

## 📚 Table of Contents

- [Quick Start](#-quick-start)
- [Service Overview](#-service-overview)
- [Which Service Should I Use?](#-which-service-should-i-use)
- [Demos](#-demos)
- [Use Cases & Examples](#-use-cases--examples)
- [Limits & Quotas](#-limits--quotas)
- [Resources](#-resources)

---

## 🚀 Quick Start

### Prerequisites

```bash
# 1. Set your project
export PROJECT_ID="your-project-id"
gcloud config set project $PROJECT_ID

# 2. Enable required APIs
gcloud services enable \
  cloudscheduler.googleapis.com \
  cloudtasks.googleapis.com \
  eventarc.googleapis.com \
  workflows.googleapis.com \
  cloudfunctions.googleapis.com \
  run.googleapis.com

# 3. Set region
export REGION=us-central1
```

### Run a Demo

Each demo is self-contained with setup, trigger, and cleanup scripts:

```bash
cd cloud-scheduler-demo
./setup.sh      # Create resources
./trigger.sh    # Test the service
./cleanup.sh    # Remove everything
```

---

## 🎯 Service Overview

| Service | Purpose | Trigger | Best For |
|---------|---------|---------|----------|
| **🕐 Cloud Scheduler** | Cron jobs | Time-based | Periodic tasks (backups, reports) |
| **📋 Cloud Tasks** | Task queuing | API call | Async work with retries (emails, processing) |
| **🎯 Eventarc** | Event routing | Events (90+ sources) | Reacting to GCP events (file uploads, DB changes) |
| **🔄 Workflows** | Service orchestration | Manual/scheduled/event | Multi-step processes (ETL, approvals) |

### 🕐 Cloud Scheduler
> **"Run this every Monday at 9 AM"**

- **What**: Fully managed cron job service
- **When**: Time-based scheduling (hourly, daily, weekly, etc.)
- **Example**: Generate daily reports, clean up old data, send weekly emails

```bash
# Schedule a daily backup at 2 AM
gcloud scheduler jobs create http daily-backup \
  --schedule="0 2 * * *" \
  --uri="https://myapp.com/backup"
```

### 📋 Cloud Tasks
> **"Do this in the background, retry if it fails"**

- **What**: Asynchronous task queue with rate limiting
- **When**: Offload work from user requests, need guaranteed delivery
- **Example**: Send emails, resize images, process payments

```python
# Queue a task to process uploaded image
task = {
    'http_request': {
        'http_method': 'POST',
        'url': 'https://worker.com/resize',
        'body': json.dumps({'image_id': '12345'})
    }
}
client.create_task(parent=queue_path, task=task)
```

### 🎯 Eventarc
> **"When this happens, do that"**

- **What**: Event-driven architecture with 90+ event sources
- **When**: React to GCP service changes (Storage uploads, DB updates, builds)
- **Example**: Process files on upload, index on DB insert, deploy on build success

```bash
# Trigger Cloud Run when file uploaded to bucket
gcloud eventarc triggers create storage-trigger \
  --destination-run-service=process-file \
  --event-filters="type=google.cloud.storage.object.v1.finalized" \
  --event-filters="bucket=my-bucket"
```

### 🔄 Workflows
> **"Do step 1, then step 2, if that works do step 3..."**

- **What**: Serverless orchestration with state management
- **When**: Multi-step processes, complex logic, error handling
- **Example**: Order processing, ETL pipelines, approval workflows

```yaml
# Multi-step order processing
- validate: call: http.post
- charge: call: payment_api
- ship: call: shipping_api
- notify: call: email_api
```

---

## 🤔 Which Service Should I Use?

### Decision Tree

```
Need to run on a schedule? 
  ├─ Yes → Cloud Scheduler
  └─ No ↓

Reacting to GCP events (storage, DB, builds)?
  ├─ Yes → Eventarc
  └─ No ↓

Multiple steps with conditional logic?
  ├─ Yes → Workflows
  └─ No ↓

Async task with retries and rate limiting?
  └─ Yes → Cloud Tasks
```

### Common Scenarios

| Scenario | Solution |
|----------|----------|
| 📅 Daily database backup | **Cloud Scheduler** |
| 📧 Send email after user signup | **Cloud Tasks** |
| 🖼️ Resize image on upload | **Eventarc** + Cloud Functions |
| 🛒 Multi-step order processing | **Workflows** |
| 🔄 Sync data to 3rd party API (rate-limited) | **Cloud Tasks** |
| 📊 Generate monthly reports | **Cloud Scheduler** + Workflows |
| 🎬 Video transcoding pipeline | **Eventarc** + Workflows |

### Quick Comparison

#### ✅ Use Cloud Scheduler When:
- Tasks run on a **fixed schedule** (every hour, daily, weekly)
- Simple HTTP calls or Pub/Sub messages
- Don't need complex retry logic

#### ✅ Use Cloud Tasks When:
- Offloading work from **user requests** (don't make users wait)
- Need **guaranteed delivery** with retries
- Must **rate-limit** API calls
- Processing **independent tasks** at scale

#### ✅ Use Eventarc When:
- Reacting to **GCP service events** (Storage, Firestore, BigQuery)
- Building **event-driven** architectures
- Need **real-time** reactions (not polling)

#### ✅ Use Workflows When:
- **Multiple services** need coordination
- Complex **conditional logic** required
- Need **error handling** and compensation
- **Long-running** processes (minutes to hours)

---

## 🧪 Demos

Each demo includes complete setup, trigger, and cleanup scripts:

### 1. [Cloud Scheduler Demo](./cloud-scheduler-demo/)
**Schedule periodic HTTP calls**
- Cron-based scheduling
- HTTP endpoint invocation
- Retry configuration

### 2. [Cloud Tasks Demo](./cloud-tasks-demo/)
**Queue background tasks**
- Task queue creation
- Rate-limited processing
- Retry & deduplication

### 3. [Eventarc Demo](./eventarc-demo/)
**React to Cloud Storage events**
- Event-driven triggers
- Cloud Storage integration
- Cloud Run deployment

### 4. [Workflows Demo](./workflows-demo/)
**Orchestrate multi-step processes**
- Sequential & parallel execution
- Error handling
- API integration

---

## 💡 Use Cases & Examples

<details>
<summary><b>🕐 Cloud Scheduler Examples</b></summary>

### ✅ Good Use Cases

**1. Database Maintenance**
```bash
# Run VACUUM on PostgreSQL nightly
gcloud scheduler jobs create http db-vacuum \
  --schedule="0 2 * * *" \
  --uri="https://db-admin.com/vacuum"
```

**2. Cache Warming**
```bash
# Refresh product catalog every hour
gcloud scheduler jobs create http cache-refresh \
  --schedule="0 * * * *" \
  --uri="https://api.com/refresh-cache"
```

**3. Report Generation**
```bash
# Generate sales report every Monday at 9 AM
gcloud scheduler jobs create http weekly-report \
  --schedule="0 9 * * 1" \
  --uri="https://reports.com/generate"
```

### ❌ Don't Use For

- Reacting to events → Use **Eventarc**
- Complex multi-step logic → Use **Workflows**
- High-reliability tasks needing many retries → Use **Cloud Tasks**

</details>

<details>
<summary><b>📋 Cloud Tasks Examples</b></summary>

### ✅ Good Use Cases

**1. Image Processing After Upload**
```python
# Don't make user wait for image resize
def handle_upload(request):
    image_id = save_to_storage(request.files['image'])
    
    # Queue background task
    task = {
        'http_request': {
            'url': 'https://worker.com/resize',
            'body': json.dumps({'image_id': image_id})
        }
    }
    tasks_client.create_task(parent=queue, task=task)
    
    return {'status': 'uploaded', 'id': image_id}  # instant response
```

**2. Rate-Limited API Sync**
```python
# Sync 10,000 users to CRM at max 100/sec
queue_config = {
    'rate_limits': {
        'max_dispatches_per_second': 100
    }
}

for user in users:
    task = create_sync_task(user)
    tasks_client.create_task(parent=queue, task=task)
```

**3. Reliable Payment Processing**
```python
# Retry failed charges automatically
queue_config = {
    'retry_config': {
        'max_attempts': 5,
        'min_backoff': '10s',
        'max_backoff': '300s'
    }
}
```

### ❌ Don't Use For

- Time-based scheduling → Use **Cloud Scheduler**
- Reacting to GCP events → Use **Eventarc**
- Multi-step orchestration → Use **Workflows**

</details>

<details>
<summary><b>🎯 Eventarc Examples</b></summary>

### ✅ Good Use Cases

**1. File Processing on Upload**
```bash
# Automatically process files uploaded to bucket
gcloud eventarc triggers create file-processor \
  --destination-run-service=process-file \
  --event-filters="type=google.cloud.storage.object.v1.finalized" \
  --event-filters="bucket=uploads"
```

**2. Deploy on Build Success**
```bash
# Auto-deploy when Cloud Build completes
gcloud eventarc triggers create auto-deploy \
  --destination-run-service=deployer \
  --event-filters="type=google.cloud.cloudbuild.build.v1.StatusChanged" \
  --event-filters="buildStatus=SUCCESS"
```

**3. Database Change Notifications**
```bash
# Send notification when Firestore document created
gcloud eventarc triggers create new-order \
  --destination-run-service=notifier \
  --event-filters="type=google.cloud.firestore.document.v1.created" \
  --event-filters="database=(default)"
```

### ❌ Don't Use For

- Scheduled tasks → Use **Cloud Scheduler**
- Rate-limited processing → Use **Cloud Tasks**
- Complex workflows → Use **Workflows**

</details>

<details>
<summary><b>🔄 Workflows Examples</b></summary>

### ✅ Good Use Cases

**1. Order Processing Pipeline**
```yaml
- validate_order:
    call: http.post
    args:
      url: ${validate_url}
      body: ${order}
    result: validation

- charge_payment:
    call: http.post
    args:
      url: ${payment_url}
      body: ${order.payment}
    result: charge

- update_inventory:
    call: http.post
    args:
      url: ${inventory_url}
      body: ${order.items}

- send_confirmation:
    call: http.post
    args:
      url: ${email_url}
      body: ${order.customer}
```

**2. ETL with Error Handling**
```yaml
- extract:
    try:
      call: http.get
      args:
        url: ${source_api}
      result: data
    retry:
      max_attempts: 3
      backoff: exponential

- transform:
    call: http.post
    args:
      url: ${transform_service}
      body: ${data}
    result: transformed

- load:
    call: http.post
    args:
      url: ${bigquery_api}
      body: ${transformed}
```

**3. Parallel Processing & Aggregation**
```yaml
- parallel_calls:
    parallel:
      shared: [results]
      branches:
        - call_api_1:
            call: http.get
            args:
              url: ${api1}
            result: results.api1
        - call_api_2:
            call: http.get
            args:
              url: ${api2}
            result: results.api2
        - call_api_3:
            call: http.get
            args:
              url: ${api3}
            result: results.api3

- aggregate:
    assign:
      - combined: ${results.api1 + results.api2 + results.api3}
```

### ❌ Don't Use For

- Simple independent tasks → Use **Cloud Tasks**
- High-frequency short tasks → Use **Cloud Functions**
- Just reacting to events → Use **Eventarc** + Cloud Functions

</details>

---

## 📊 Limits & Quotas

### Quick Reference

| Service | Key Limits | Request Increase |
|---------|-----------|------------------|
| **Cloud Scheduler** | 100K jobs/region, 3 retry attempts | [View Quotas](https://cloud.google.com/scheduler/quotas) |
| **Cloud Tasks** | 1M tasks/queue, 500/sec dispatch | [View Quotas](https://cloud.google.com/tasks/docs/quotas) |
| **Eventarc** | 200 triggers/location, 512KB events | [View Quotas](https://cloud.google.com/eventarc/quotas) |
| **Workflows** | 1 year max duration, 1MB definition | [View Quotas](https://cloud.google.com/workflows/quotas) |

<details>
<summary><b>View Detailed Limits</b></summary>

### Cloud Scheduler
- Jobs per region: **100,000**
- Min frequency: **1 minute**
- Retry attempts: **3**
- HTTP timeout: **30 minutes**
- Payload size: **100 KB**

### Cloud Tasks
- Tasks per queue: **1,000,000**
- Dispatch rate: **500/sec** (configurable)
- Concurrent tasks: **1,000** (configurable)
- Payload size: **100 KB** (HTTP), **1 MB** (App Engine)
- Max task age: **31 days**
- Retry duration: **Unlimited** (configurable)

### Eventarc
- Triggers per location: **200**
- Event size: **512 KB**
- Delivery timeout: **10 minutes**
- Filters per trigger: **10**
- Event retention: **7 days**

### Workflows
- Workflows per region: **1,000**
- Definition size: **1 MB**
- Max duration: **1 year**
- Concurrent executions: **10,000**
- Subworkflow depth: **10 levels**
- Parallel branches: **100,000**

</details>

---

## 💰 Pricing

| Service | Pricing Model | Free Tier |
|---------|--------------|-----------|
| **Cloud Scheduler** | $0.10/job/month | 3 jobs free |
| **Cloud Tasks** | $0.40 per million operations | 1M operations/month free |
| **Eventarc** | Channel usage charges | Varies by channel |
| **Workflows** | $0.01 per 1,000 steps | 5,000 steps/month free |

📖 Official pricing: [Scheduler](https://cloud.google.com/scheduler/pricing) • [Tasks](https://cloud.google.com/tasks/pricing) • [Eventarc](https://cloud.google.com/eventarc/pricing) • [Workflows](https://cloud.google.com/workflows/pricing)

---

## 🔗 Resources

### Official Documentation

**Cloud Scheduler**
- [📘 Overview](https://cloud.google.com/scheduler/docs) | [🚀 Quickstart](https://cloud.google.com/scheduler/docs/quickstart) | [📖 Cron Syntax](https://cloud.google.com/scheduler/docs/configuring/cron-job-schedules)

**Cloud Tasks**
- [📘 Overview](https://cloud.google.com/tasks/docs) | [🚀 Quickstart](https://cloud.google.com/tasks/docs/quickstart) | [⚙️ Queue Config](https://cloud.google.com/tasks/docs/configuring-queues)

**Eventarc**
- [📘 Overview](https://cloud.google.com/eventarc/docs) | [🚀 Quickstart](https://cloud.google.com/eventarc/docs/quickstart) | [🎯 Event Sources](https://cloud.google.com/eventarc/docs/event-providers-targets)

**Workflows**
- [📘 Overview](https://cloud.google.com/workflows/docs) | [🚀 Quickstart](https://cloud.google.com/workflows/docs/quickstart-console) | [📝 Syntax Reference](https://cloud.google.com/workflows/docs/reference/syntax)

### Related Services
- [Cloud Functions](https://cloud.google.com/functions/docs) - Execute code in response to events
- [Cloud Run](https://cloud.google.com/run/docs) - Run containers serverless
- [Pub/Sub](https://cloud.google.com/pubsub/docs) - Messaging and streaming

---

## 📝 License

[MIT License](LICENSE) - Feel free to use these demos for learning and development.

---

## 🤝 Contributing

Issues and pull requests welcome! Help improve these demos for the community.

---

**Made with ☁️ by the community**
