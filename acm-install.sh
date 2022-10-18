#### VARS

BILLING_ACCOUNT_ID=xxxx-xxxx-xxxx
PROJECT_NAME=project-name
CLUSTER_NAME=my-cluster-name
export CLUSTER_BOOTSTRAP_URL="git@github.com:85matthew/acm_cluster_bootstrap.git"
#####

gcloud config set project $PROJECT_NAME
gcloud alpha billing accounts projects link $PROJECT_NAME --billing-account $BILLING_ACCOUNT_ID


###
# From https://cloud.google.com/anthos-config-management/docs/tutorials/create-configure-cluster
###

export PROJECT_ID=$(gcloud config get-value project)
export ZONE=us-central1-a
export REGION=us-central1
export CLUSTER_LOCATION=$ZONE   # or region here 
export CWD=$(pwd)

# Enable config management (only if not on GKE)
gcloud services enable anthos.googleapis.com
gcloud beta container hub config-management enable

# Register cluster (if not already registered)
gcloud container hub memberships register ${CLUSTER_NAME} \
 --gke-uri=https://container.googleapis.com/v1/projects/${PROJECT_ID}/locations/${CLUSTER_LOCATION}/clusters/${CLUSTER_NAME} \
 --enable-workload-identity

# Generate ssh keypair for github access (if private repo)
ssh-keygen -t rsa -b 4096 -C "85matthew" -N '' -f $CWD/ssh_keys

kubectl create ns config-management-system && \
kubectl create secret generic git-creds \
 --namespace=config-management-system \
 --from-file=ssh=$CWD/ssh_keys

# Create configSync manifest

# apply-spec.yaml
cat > apply-spec.yaml << ENDOFFILE
applySpecVersion: 1
spec:
  configSync:
    # Set to true to install and enable Config Sync
    enabled: true
ENDOFFILE

# apply-spec.yaml
cat > apply-spec.yaml << ENDOFFILE
applySpecVersion: 1
spec:
  configSync:
    # Set to true to install and enable Config Sync
    enabled: true
    # If you don't have a Git repository, omit the following fields. You
    # can configure them later.
    sourceFormat: FORMAT
    syncRepo: REPO
    syncBranch: BRANCH
    secretType: TYPE
    gcpServiceAccountEmail: EMAIL
    policyDir: DIRECTORY
    # the `preventDrift` field is supported in Anthos Config Management version 1.10.0 and later.
    preventDrift: PREVENT_DRIFT
ENDOFFILE


# apply-spec.yaml
cat > apply-spec.yaml << ENDOFFILE
applySpecVersion: 1
spec:
  configSync:
    enabled: true
    # Since your repository is using Helm, you need to use an unstructured repository.
    sourceFormat: unstructured
    syncRepo: $CLUSTER_BOOTSTRAP_URL
    syncBranch: main
    secretType: ssh
ENDOFFILE

# apply config 
gcloud beta container hub config-management apply \
    --membership=$CLUSTER_NAME \
    --config=$CWD/apply-spec.yaml \
    --project=$PROJECT_ID

### Verify status
gcloud alpha container hub config-management status \
    --project=$PROJECT_ID

nomos status