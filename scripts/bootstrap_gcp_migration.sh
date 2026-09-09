#!/usr/bin/env bash
set -euo pipefail

PROJECT_ID="${GCP_PROJECT_ID:-fc-teugn}"
REGION="${GCP_REGION:-europe-west3}"
REPOSITORY="${GITHUB_REPOSITORY:-tbauer-oss/FC-Teugn}"
BUCKET="${GCS_BUCKET:-fc-teugn.firebasestorage.app}"
ARTIFACT_REPOSITORY="fc-teugn"
DEPLOY_SA_ID="fc-teugn-github"
RUNTIME_SA_ID="fc-teugn-runtime"
WIF_POOL="github"
WIF_PROVIDER="fc-teugn"

DEPLOY_SA="${DEPLOY_SA_ID}@${PROJECT_ID}.iam.gserviceaccount.com"
RUNTIME_SA="${RUNTIME_SA_ID}@${PROJECT_ID}.iam.gserviceaccount.com"

echo "Preparing Google Cloud project ${PROJECT_ID} for FC Teugn Talents migration..."

gcloud projects describe "$PROJECT_ID" >/dev/null

gcloud config set project "$PROJECT_ID" --quiet

PROJECT_NUMBER="$(gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)')"
if [ -z "$PROJECT_NUMBER" ]; then
  echo "Could not resolve project number for ${PROJECT_ID}." >&2
  exit 1
fi

# Cloud Run and Artifact Registry require billing. This check is advisory because
# not every account has permission to inspect the billing relationship.
if billing_state="$(gcloud billing projects describe "$PROJECT_ID" --format='value(billingEnabled)' 2>/dev/null)"; then
  if [ "$billing_state" != "True" ] && [ "$billing_state" != "true" ]; then
    echo "ERROR: Billing is not enabled for ${PROJECT_ID}. Enable billing before continuing." >&2
    exit 1
  fi
else
  echo "WARNING: Billing status could not be read. Cloud Run requires billing to be enabled."
fi

echo "Enabling required Google APIs..."
gcloud services enable \
  run.googleapis.com \
  artifactregistry.googleapis.com \
  secretmanager.googleapis.com \
  cloudscheduler.googleapis.com \
  iam.googleapis.com \
  iamcredentials.googleapis.com \
  sts.googleapis.com \
  cloudresourcemanager.googleapis.com \
  firebase.googleapis.com \
  firebasehosting.googleapis.com \
  firebasestorage.googleapis.com \
  fcm.googleapis.com \
  --project "$PROJECT_ID" \
  --quiet

create_service_account_if_missing() {
  local account_id="$1"
  local display_name="$2"
  if ! gcloud iam service-accounts describe "${account_id}@${PROJECT_ID}.iam.gserviceaccount.com" \
    --project "$PROJECT_ID" >/dev/null 2>&1; then
    gcloud iam service-accounts create "$account_id" \
      --project "$PROJECT_ID" \
      --display-name "$display_name"
  fi
}

create_service_account_if_missing "$DEPLOY_SA_ID" "FC Teugn GitHub Deployments"
create_service_account_if_missing "$RUNTIME_SA_ID" "FC Teugn Cloud Run Runtime"

if ! gcloud artifacts repositories describe "$ARTIFACT_REPOSITORY" \
  --project "$PROJECT_ID" --location "$REGION" >/dev/null 2>&1; then
  gcloud artifacts repositories create "$ARTIFACT_REPOSITORY" \
    --project "$PROJECT_ID" \
    --location "$REGION" \
    --repository-format docker \
    --description "FC Teugn Talents Cloud Run images" \
    --quiet
fi

if ! gcloud storage buckets describe "gs://${BUCKET}" --project "$PROJECT_ID" >/dev/null 2>&1; then
  echo "ERROR: Expected Firebase Storage bucket gs://${BUCKET} does not exist." >&2
  echo "Open Firebase Console > Storage for project ${PROJECT_ID} once, initialize Storage, then rerun this script." >&2
  exit 1
fi

echo "Granting deployment permissions..."
DEPLOY_ROLES=(
  roles/run.admin
  roles/artifactregistry.writer
  roles/secretmanager.admin
  roles/cloudscheduler.admin
  roles/firebasehosting.admin
  roles/serviceusage.serviceUsageConsumer
)
for role in "${DEPLOY_ROLES[@]}"; do
  gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member "serviceAccount:${DEPLOY_SA}" \
    --role "$role" \
    --condition=None \
    --quiet >/dev/null
 done

echo "Granting Cloud Run runtime permissions..."
RUNTIME_ROLES=(
  roles/secretmanager.secretAccessor
  roles/firebasecloudmessaging.admin
)
for role in "${RUNTIME_ROLES[@]}"; do
  gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member "serviceAccount:${RUNTIME_SA}" \
    --role "$role" \
    --condition=None \
    --quiet >/dev/null
 done

# Both identities need object access during the migration; the runtime keeps it
# afterwards for uploads/downloads. Bucket-level IAM avoids project-wide Storage Admin.
gcloud storage buckets add-iam-policy-binding "gs://${BUCKET}" \
  --member "serviceAccount:${DEPLOY_SA}" \
  --role roles/storage.objectAdmin \
  --quiet >/dev/null

gcloud storage buckets add-iam-policy-binding "gs://${BUCKET}" \
  --member "serviceAccount:${RUNTIME_SA}" \
  --role roles/storage.objectAdmin \
  --quiet >/dev/null

# GitHub deploy identity is allowed to attach the dedicated runtime identity.
gcloud iam service-accounts add-iam-policy-binding "$RUNTIME_SA" \
  --project "$PROJECT_ID" \
  --member "serviceAccount:${DEPLOY_SA}" \
  --role roles/iam.serviceAccountUser \
  --quiet >/dev/null

if ! gcloud iam workload-identity-pools describe "$WIF_POOL" \
  --project "$PROJECT_ID" --location global >/dev/null 2>&1; then
  gcloud iam workload-identity-pools create "$WIF_POOL" \
    --project "$PROJECT_ID" \
    --location global \
    --display-name "GitHub Actions" \
    --quiet
fi

if ! gcloud iam workload-identity-pools providers describe "$WIF_PROVIDER" \
  --project "$PROJECT_ID" --location global --workload-identity-pool "$WIF_POOL" >/dev/null 2>&1; then
  gcloud iam workload-identity-pools providers create-oidc "$WIF_PROVIDER" \
    --project "$PROJECT_ID" \
    --location global \
    --workload-identity-pool "$WIF_POOL" \
    --display-name "FC Teugn GitHub" \
    --issuer-uri "https://token.actions.githubusercontent.com" \
    --attribute-mapping "google.subject=assertion.sub,attribute.repository=assertion.repository,attribute.ref=assertion.ref" \
    --attribute-condition "assertion.repository=='${REPOSITORY}'" \
    --quiet
fi

POOL_NAME="$(gcloud iam workload-identity-pools describe "$WIF_POOL" \
  --project "$PROJECT_ID" --location global --format='value(name)')"
PROVIDER_NAME="$(gcloud iam workload-identity-pools providers describe "$WIF_PROVIDER" \
  --project "$PROJECT_ID" --location global --workload-identity-pool "$WIF_POOL" --format='value(name)')"

WIF_MEMBER="principalSet://iam.googleapis.com/${POOL_NAME}/attribute.repository/${REPOSITORY}"

gcloud iam service-accounts add-iam-policy-binding "$DEPLOY_SA" \
  --project "$PROJECT_ID" \
  --member "$WIF_MEMBER" \
  --role roles/iam.workloadIdentityUser \
  --quiet >/dev/null

cat <<EOF

============================================================
Google Cloud bootstrap completed.

Use these GitHub repository VARIABLES:

GCP_PROJECT_ID=${PROJECT_ID}
GCP_WORKLOAD_IDENTITY_PROVIDER=${PROVIDER_NAME}
GCP_SERVICE_ACCOUNT=${DEPLOY_SA}
GCS_BUCKET=${BUCKET}

Runtime service account (already configured):
${RUNTIME_SA}

Next safe order after the variables are stored in GitHub:
1. Migrate Vercel Environment to Google Secret Manager
2. Deploy Backend API to Cloud Run
3. Migrate Vercel Blobs to Google Cloud Storage (dry run first)
4. Deploy Flutter Web to Firebase Hosting
5. Configure Cloud Scheduler Reminder Job with enable=false

Do NOT disable Vercel or change DNS yet.
============================================================
EOF
