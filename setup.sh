#!/bin/bash
gcloud container clusters create "acm-cluster" --zone "us-central1-c" --workload-pool "seismic-anthos-0.svc.id.goog"

# START ABM setup
## Create allow SSH from IAP network tag
gcloud compute firewall-rules create allow-ssh-ingress-from-iap \
  --direction=INGRESS \
  --action=allow \
  --rules=tcp:22 \
  --source-ranges=35.235.240.0/20
gcloud compute firewall-rules create allow-ssh \
  --direction=INGRESS \
  --priority=1000 \
  --network=default \
  --action=ALLOW \
  --rules=tcp:22 \
  --source-tags=allow-ssh

## Create the linux admin workstation
gcloud compute instances create abm-linux-admin --zone=us-central1-a --tags=allow-ssh-ingress-from-iap,allow-ssh --machine-type=e2-medium --subnet=default --scopes=https://www.googleapis.com/auth/cloud-platform --create-disk=image=projects/ubuntu-os-cloud/global/images/ubuntu-1804-bionic-v20221005,mode=rw,size=10

gcloud compute ssh --zone us-central1-a abm-linux-admin --tunnel-through-iap -- 'sudo apt-get -y install \
  apt-transport-https \
  ca-certificates \
  curl \
  gnupg-agent \
  software-properties-common \
  docker.io'

## Create ABM nodes
gcloud compute instances create abm-worker-0 --zone=us-central1-a --tags=allow-ssh-ingress-from-iap --machine-type=e2-standard-4 --subnet=default --scopes=https://www.googleapis.com/auth/cloud-platform --create-disk=image=projects/ubuntu-os-cloud/global/images/ubuntu-1804-bionic-v20221005,mode=rw,size=128
gcloud compute instances create abm-cp-0 --zone=us-central1-a --tags=allow-ssh-ingress-from-iap --machine-type=e2-standard-4 --subnet=default --scopes=https://www.googleapis.com/auth/cloud-platform --create-disk=image=projects/ubuntu-os-cloud/global/images/ubuntu-1804-bionic-v20221005,mode=rw,size=128
# END ABM setup