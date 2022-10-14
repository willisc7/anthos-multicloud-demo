### Argolis Notes
* Disable org policies needed to spin up GKE cluster
* Create default network `gcloud compute networks create default --subnet-mode=auto --mtu=1460 --bgp-routing-mode=regional`
* Give the default compute engine service account Owner permissions (dont do this in production)
* Make sure the key-value pair of `enable-oslogin:true` under the Compute Engine > Metadata is removed

### Initial Setup
1. Run `./setup.sh`

### Add GKE cluster to Anthos Config Management
1. Navigate to the Config Management page and do the following:
    * Click `NEW SETUP`
    * Select the `acm-cluster` cluster and click `NEXT`
    * Click `NEXT` to leave defaults on Policy Controller step
    * Change `Repository` to `Custom` and put the URL `https://github.com/willisc7/anthos-multicloud-demo`
    * Click `SHOW ADVANCED SETTINGS` and set `Configuration directory` to `/config-sync`
    * Click `COMPLETE`

### Create an Anthos Bare Metal cluster
1. SSH into `abm-worker-0` and do the following:
    * Turn on (temporarily) SSH root login and password use by running `sudo vim /etc/ssh/sshd_config` and setting `PermitRootLogin yes` and `PasswordAuthentication yes`
    * Restart sshd `sudo systemctl restart sshd`
    * Set the root password to something you'll remember with `sudo passwd`
    * Repeat these steps for `abm-cp-0`
1. Copy SSH keys to ABM nodes
    * `gcloud compute ssh --zone us-central1-a abm-linux-admin --tunnel-through-iap`
    * `ssh-keygen -t rsa -f ~/.ssh/abm -N ''`
    * `ssh-copy-id -i ~/.ssh/abm root@WORKER_INTERNAL_IP`
    * `ssh-copy-id -i ~/.ssh/abm root@CP_INTERNAL_IP`
1. SSH into `abm-worker-0` and do the following:
    * Turn off password authentication by running `sudo vim /etc/ssh/sshd_config` and setting `PasswordAuthentication no`
    * Restart sshd `sudo systemctl restart sshd`
    * Repeat these steps for `abm-cp-0`
1. Make sure `adm-linux-admin` can get into each machine using the SSH key you generated:
    ```
    ssh -o IdentitiesOnly=yes -i ~/.ssh/abm root@WORKER_INTERNAL_IP
    exit
    ssh -o IdentitiesOnly=yes -i ~/.ssh/abm root@CP_INTERNAL_IP
    exit
    ```
1. SSH to abm-linux-admin
    ```
    gcloud compute ssh --zone us-central1-a abm-linux-admin --tunnel-through-iap
    ```
1. Install `bmctl`
    ```
    cd ~
    mkdir baremetal
    cd baremetal
    gsutil cp gs://anthos-baremetal-release/bmctl/1.13.0/linux-amd64/bmctl bmctl
    chmod a+x bmctl
    ./bmctl -h
    ```
1. Create config file
    ```
    ./bmctl create config -c cluster1 \
      --enable-apis --create-service-accounts \
      --project-id=seismic-anthos-0
    ```
1. `vim ./bmctl-workspace/abm-cluster-0/abm-cluster-0.yaml` and change the following:
    * `sshPrivateKeyPath: /home/admin_/.ssh/abm`
    * `spec.controlPlane.nodePoolSpec.nodes[address]: 10.128.0.7`
    * uncomment `spec.loadBalancer.vips.controlPlaneVIP`
    * uncomment `spec.loadBalancer.vips.ingressVIP`