### TODO
* Get rid of the need for sudo
* Fix the need to manually copy SSH pub key

### Argolis Notes
* Run fix-argolis script here: https://github.com/yeltnerb/baremetal1/blob/main/fix-argolis.sh
* Create default network `gcloud compute networks create default --subnet-mode=auto --mtu=1460 --bgp-routing-mode=regional`
* Allow internal communication on the default network `gcloud compute firewall-rules create allow-internal --direction=INGRESS --priority=1000 --network=default --action=ALLOW --rules=all --source-ranges=10.128.0.0/9`

### Create an ABM Cluster
1. Run `chmod +x ./abm-on-gce.sh && ./abm-on-gce.sh`
1. If the command fails with SSH errors, you need to manually copy the SSH public key from the abm-ws VM to the other VMs
    * `gcloud compute ssh abm-ws --zone us-central1-a --tunnel-through-iap`
    * `sudo su -`
    * Copy the contents of `~/.ssh/id_rsa.pub`
    * `gcloud compute ssh abm-cp1 --zone us-central1-a --tunnel-through-iap`
    * `sudo su -`
    * Paste the public key in the `~/.ssh/authorized_keys` file
    * Repeate for abm-cp2, abm-cp3, abm-w1, abm-w2

### Create a GKE Cluster
1. `gcloud container clusters create "acm-cluster" --zone "us-central1-c" --workload-pool "seismic-anthos-0.svc.id.goog"`

### Add GKE cluster to Anthos Config Management
1. Navigate to the Config Management page and do the following:
    * Click `NEW SETUP`
    * Select the `acm-cluster` cluster and click `NEXT`
    * Click `NEXT` to leave defaults on Policy Controller step
    * Change `Repository` to `Custom` and put the URL `https://github.com/willisc7/anthos-multicloud-demo`
    * Click `SHOW ADVANCED SETTINGS` and set `Configuration directory` to `/config-sync`
    * Click `COMPLETE`