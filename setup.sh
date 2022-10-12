#!/bin/bash
gcloud compute networks create default --subnet-mode=auto --mtu=1460 --bgp-routing-mode=regional

gcloud container clusters create "acm-cluster" --zone "us-central1-c" --workload-pool "seismic-anthos-0.svc.id.goog"