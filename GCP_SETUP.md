# GCP One-Time Setup

Run these commands once to bootstrap the GCP project. You'll need to be authenticated
(`gcloud auth login`) and have billing set up.

```bash
gcloud projects create homehd-personal --name="Home HD"
gcloud config set project homehd-personal
gcloud billing accounts list   # note your BILLING_ACCOUNT_ID
gcloud billing projects link homehd-personal --billing-account=<BILLING_ACCOUNT_ID>

# Set a $5/month budget alert BEFORE enabling any paid API
gcloud billing budgets create \
  --billing-account=<BILLING_ACCOUNT_ID> \
  --display-name="homehd-budget" \
  --budget-amount=5USD \
  --threshold-rules-percent=100

# Enable all APIs needed across all three phases
gcloud services enable \
  firebase.googleapis.com \
  run.googleapis.com \
  artifactregistry.googleapis.com \
  cloudbuild.googleapis.com \
  secretmanager.googleapis.com \
  --project=homehd-personal

# Initialize Firebase (interactive browser login required)
firebase login
firebase projects:addfirebase homehd-personal
firebase use --add homehd-personal   # alias: default
```
