
### EDIT VARS ###
BILLING_ACCOUNT_ID=billing-id
PROJECT_NAME=project-name
CREATE_VPC_NAME=default
ROUTER_NAME=router
CLUSTER_NAME=abmc
export ZONE=us-central1-a
export REGION=us-central1
### (end) EDIT VARS ###


MACHINE_TYPE=n1-standard-8
VM_PREFIX=abm
VM_WS=$VM_PREFIX-ws
VM_CP1=$VM_PREFIX-cp1
VM_CP2=$VM_PREFIX-cp2
VM_CP3=$VM_PREFIX-cp3
VM_W1=$VM_PREFIX-w1
VM_W2=$VM_PREFIX-w2
gcloud config set project $PROJECT_NAME


gcloud projects create $PROJECT_NAME --name $PROJECT_NAME
gcloud config set project $PROJECT_NAME
gcloud alpha billing accounts projects link $PROJECT_NAME --billing-account $BILLING_ACCOUNT_ID
gcloud compute project-info add-metadata --metadata enable-oslogin=FALSE


###
# From  https://cloud.google.com/anthos/clusters/docs/bare-metal/latest/try/gce-vms
###

export PROJECT_ID=$(gcloud config get-value project)

# Create the variables and arrays needed for all the commands on this page:
declare -a VMs=("$VM_WS" "$VM_CP1" "$VM_CP2" "$VM_CP3" "$VM_W1" "$VM_W2")
declare -a IPs=()


gcloud services enable orgpolicy.googleapis.com

cat > sa_key_creation.yaml << ENDOFFILE
name: projects/$PROJECT_ID/policies/iam.disableServiceAccountKeyCreation 
spec:
  rules:
  - enforce: false
ENDOFFILE

cat > vmCanIpForward.yaml << ENDOFFILE
name: projects/$PROJECT_ID/policies/compute.vmCanIpForward
spec:
  rules:
  - allowAll: true
ENDOFFILE


gcloud org-policies set-policy sa_key_creation.yaml
gcloud org-policies set-policy vmCanIpForward.yaml

gcloud iam service-accounts create baremetal-gcr

gcloud iam service-accounts keys create bm-gcr.json \
--iam-account=baremetal-gcr@${PROJECT_ID}.iam.gserviceaccount.com

# Enable Services and Add IAM Permissions
gcloud services enable \
    anthos.googleapis.com \
    anthosaudit.googleapis.com \
    anthosgke.googleapis.com \
    cloudresourcemanager.googleapis.com \
    connectgateway.googleapis.com \
    container.googleapis.com \
    gkeconnect.googleapis.com \
    gkehub.googleapis.com \
    serviceusage.googleapis.com \
    stackdriver.googleapis.com \
    monitoring.googleapis.com \
    logging.googleapis.com \
    opsconfigmonitoring.googleapis.com

gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:baremetal-gcr@$PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/gkehub.connect"

gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:baremetal-gcr@$PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/gkehub.admin"

gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:baremetal-gcr@$PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/logging.logWriter"

gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:baremetal-gcr@$PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/monitoring.metricWriter"

gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:baremetal-gcr@$PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/monitoring.dashboardEditor"

gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:baremetal-gcr@$PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/stackdriver.resourceMetadata.writer"

gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:baremetal-gcr@$PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/opsconfigmonitoring.resourceMetadata.writer"

gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:baremetal-gcr@$PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/compute.osAdminLogin"

gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:baremetal-gcr@$PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/iam.serviceAccountKeyAdmin"

gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:baremetal-gcr@$PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/osconfig.serviceAgent"


# Create the VPC
gcloud compute networks create $CREATE_VPC_NAME --project=$PROJECT_NAME --subnet-mode=auto --mtu=1460 --bgp-routing-mode=regional

# Create a cloud router
gcloud compute routers create router --project=$PROJECT_NAME --region=$REGION --network=$CREATE_VPC_NAME --asn=64512

# Create NAT gateway
gcloud compute routers nats create nat-gw \
    --router=$ROUTER_NAME \
    --auto-allocate-nat-external-ips \
    --nat-all-subnet-ip-ranges \
    --enable-logging \
    --region $REGION

# Firewall update
gcloud compute --project=$PROJECT_NAME firewall-rules create $CLUSTER_NAME --direction=INGRESS --priority=1000 --network=$CREATE_VPC_NAME --action=ALLOW --rules=tcp:8676 --source-ranges=0.0.0.0/0


# Firewall updates
# MY_FW_RULE=$(gcloud compute firewall-rules list --filter="name~gke-${CLUSTER_NAME}-[0-9a-z]*-master" --format 'value(name)')

# gcloud compute firewall-rules update $MY_FW_RULE --allow tcp:10250,tcp:443,tcp:15017
gcloud compute firewall-rules create allow-ssh-ingress-from-iap \
  --direction=INGRESS \
  --action=allow \
  --rules=tcp:22 \
  --source-ranges=35.235.240.0/20

# Firewall- allow internal communication, cause we're running on GCE 
gcloud compute firewall-rules create allow-internal \
  --direction=INGRESS \
  --action=allow \
  --rules=all \
  --source-ranges=10.128.0.0/16

# Create 6 VMs
for vm in "${VMs[@]}"
do
    gcloud compute instances create $vm \
              --image-family=ubuntu-2004-lts --image-project=ubuntu-os-cloud \
              --zone=${ZONE} \
              --boot-disk-size 200G \
              --boot-disk-type pd-ssd \
              --can-ip-forward \
              --network=$CREATE_VPC_NAME \
              --no-address \
              --tags http-server,https-server \
              --scopes cloud-platform \
              --machine-type $MACHINE_TYPE \
              --shielded-secure-boot \
              --shielded-vtpm \
              --shielded-integrity-monitoring \
              --service-account baremetal-gcr@$PROJECT_ID.iam.gserviceaccount.com

    IP=$(gcloud compute instances describe $vm --zone ${ZONE} \
         --format='get(networkInterfaces[0].networkIP)')
    IPs+=("$IP")
done

# #  TEMP HERE
# gcloud compute instances list | grep '$VM_PREFIX' | awk '{print $2}' | xargs gcloud --quiet compute instances delete --zone $ZONE

# Verify SSH connectivity
for vm in "${VMs[@]}"
do
    while ! gcloud compute ssh root@$vm --zone ${ZONE} --tunnel-through-iap --command "echo SSH to $vm succeeded"
    do
        echo "Trying to SSH into $vm failed. Sleeping for 5 seconds. zzzZZzzZZ"
        sleep  5
    done
done

# SSH into each server and configure a VXLAN network between them.
# We start from 10.200.0.2/24

i=2
for vm in "${VMs[@]}"
do
    gcloud compute ssh $vm --zone ${ZONE} --tunnel-through-iap << EOF
        sudo su -
        apt-get -qq update > /dev/null
        apt-get -qq install -y jq > /dev/null
        set -x
        ip link add vxlan0 type vxlan id 42 dev ens4 dstport 0
        current_ip=\$(ip --json a show dev ens4 | jq '.[0].addr_info[0].local' -r)
        echo "VM IP address is: \$current_ip"
        for ip in ${IPs[@]}; do
            if [ "\$ip" != "\$current_ip" ]; then
                bridge fdb append to 00:00:00:00:00:00 dst \$ip dev vxlan0
            fi
        done
        ip addr add 10.200.0.$i/24 dev vxlan0
        
        ip link set up dev vxlan0

EOF
    i=$((i+1))
done

# Admin VM- 10.200.0.2
# CP- 10.200.0.3, 4, 5
# Workers- 10.200.0.6, 7
#

# Install required tools on admin workstation
gcloud compute ssh $VM_WS --zone ${ZONE} --tunnel-through-iap << EOF
sudo su -
set -x

export PROJECT_ID=\$(gcloud config get-value project)
gcloud iam service-accounts keys create bm-gcr.json \
--iam-account=baremetal-gcr@\${PROJECT_ID}.iam.gserviceaccount.com

curl -LO "https://storage.googleapis.com/kubernetes-release/release/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/linux/amd64/kubectl"


chmod +x kubectl
mv kubectl /usr/local/sbin/
mkdir baremetal && cd baremetal
gsutil cp gs://anthos-baremetal-release/bmctl/1.11.2/linux-amd64/bmctl .
chmod a+x bmctl
mv bmctl /usr/local/sbin/

cd ~
echo "Installing docker"
curl -fsSL https://get.docker.com -o get-docker.sh
sh get-docker.sh
EOF

# Configure SSH access to all machines from admin workstation
# ISSUE: for some reason SSH didnt work after this. I had to manually add 
# the SSH public key to each VMs ~/.ssh/authorized_keys to get it to work
gcloud compute ssh $VM_WS --zone ${ZONE} --tunnel-through-iap --tunnel-through-iap << EOF
sudo su - 
set -x
ssh-keygen -t rsa -N "" -f /root/.ssh/id_rsa
sed 's/ssh-rsa/root:ssh-rsa/' ~/.ssh/id_rsa.pub > ssh-metadata
for vm in ${VMs[@]}
do
    gcloud compute instances add-metadata \$vm --zone ${ZONE} --metadata-from-file ssh-keys=ssh-metadata
done
EOF



# Deploy ABM cluster- create config file for hybrid cluster, run preflight checks, deploy cluster
gcloud compute ssh $VM_WS --zone ${ZONE} --tunnel-through-iap << EOF
sudo su -
set -x
export PROJECT_ID=$(gcloud config get-value project)
export clusterid=$CLUSTER_NAME
bmctl create config -c \$clusterid
cat > bmctl-workspace/\$clusterid/\$clusterid.yaml << EOB
---
gcrKeyPath: /root/bm-gcr.json
sshPrivateKeyPath: /root/.ssh/id_rsa
gkeConnectAgentServiceAccountKeyPath: /root/bm-gcr.json
gkeConnectRegisterServiceAccountKeyPath: /root/bm-gcr.json
cloudOperationsServiceAccountKeyPath: /root/bm-gcr.json
---
apiVersion: v1
kind: Namespace
metadata:
  name: cluster-\$clusterid
---
apiVersion: baremetal.cluster.gke.io/v1
kind: Cluster
metadata:
  name: \$clusterid
  namespace: cluster-\$clusterid
spec:
  type: hybrid
  anthosBareMetalVersion: 1.11.2
  gkeConnect:
    projectID: \$PROJECT_ID
  controlPlane:
    nodePoolSpec:
      clusterName: \$clusterid
      nodes:
      - address: 10.200.0.3
      - address: 10.200.0.4
      - address: 10.200.0.5
  clusterNetwork:
    pods:
      cidrBlocks:
      - 192.168.0.0/16
    services:
      cidrBlocks:
      - 172.26.232.0/24
  loadBalancer:
    mode: bundled
    ports:
      controlPlaneLBPort: 443
    vips:
      controlPlaneVIP: 10.200.0.49
      ingressVIP: 10.200.0.50
    addressPools:
    - name: pool1
      addresses:
      - 10.200.0.50-10.200.0.70
  clusterOperations:
    # might need to be this location
    location: us-central1
    projectID: \$PROJECT_ID
  storage:
    lvpNodeMounts:
      path: /mnt/localpv-disk
      storageClassName: node-disk
    lvpShare:
      numPVUnderSharedPath: 5
      path: /mnt/localpv-share
      storageClassName: standard
  nodeConfig:
    podDensity:
      maxPodsPerNode: 250
    containerRuntime: containerd
---
apiVersion: baremetal.cluster.gke.io/v1
kind: NodePool
metadata:
  name: node-pool-1
  namespace: cluster-\$clusterid
spec:
  clusterName: \$clusterid
  nodes:
  - address: 10.200.0.6
  - address: 10.200.0.7
EOB

bmctl create cluster -c \$clusterid
EOF


# Verify cluster connectivity from Cloud Shell/Workstation
# gcloud compute ssh $VM_WS --zone ${ZONE} --tunnel-through-iap << EOF
# sudo su -
# export clusterid=abmc
# # export clusterid=$CLUSTER_NAME
# export KUBECONFIG=\$HOME/bmctl-workspace/\$clusterid/\$clusterid-kubeconfig
# kubectl get nodes
# EOF

## If you want to manually log into host
#gcloud compute ssh root@$VM_WS --zone ${ZONE} --tunnel-through-iap
## Then run
#export clusterid=abmc
#export KUBECONFIG=$HOME/bmctl-workspace/$clusterid/$clusterid-kubeconfig
# do things


# Register in Google Console
# *** from the admin workstation (because that's where kubeconfig is) ***
gcloud compute ssh $VM_WS --zone ${ZONE} --tunnel-through-iap << EOF
sudo su -
gcloud alpha container hub memberships generate-gateway-rbac  \
--membership=abmc \
--role=clusterrole/cluster-admin \
--users=admin@myuserid.specificURL.com \
--project=$PROJECT_NAME \
--kubeconfig=/root/bmctl-workspace/abmc/abmc-kubeconfig \
--context=abmc-admin@mycontext \
--apply
EOF

# Google Groups Auth
# https://cloud.google.com/anthos/multicluster-management/gateway/setup-groups

# Under clusters in the console, click the login button, use GKE account auth.

# Validate that retrieving creds from Cloud workstation work
# ISSUE: this didnt work for me. Error: 
# W1018 09:42:09.886461   54510 gcp.go:120] WARNING: the gcp auth plugin is deprecated in v1.22+, unavailable in v1.25+; use gcloud instead.
# To learn more, consult https://cloud.google.com/blog/products/containers-kubernetes/kubectl-auth-changes-in-gke
# error: the server doesn't have a resource type "nodes"
# gcloud container hub memberships get-credentials abmc
# kubectl get nodes
# NAME      STATUS   ROLES                  AGE   VERSION
# abm-cp1   Ready    control-plane,master   20h   v1.22.8-gke.200
# abm-cp2   Ready    control-plane,master   19h   v1.22.8-gke.200
# abm-cp3   Ready    control-plane,master   19h   v1.22.8-gke.200
# abm-w1    Ready    worker                 19h   v1.22.8-gke.200
# abm-w2    Ready    worker                 19h   v1.22.8-gke.200



gcloud projects add-iam-policy-binding abm-$PROJECT_NAME \
  --member serviceAccount:baremetal-gcr@$PROJECT_NAME.iam.gserviceaccount.com \
  --role "roles/gkehub.connect"


# Delete cluster/VMs
# gcloud compute instances list | grep 'abm' | awk '{print $2}' | xargs gcloud --quiet compute instances delete --zone $ZONE