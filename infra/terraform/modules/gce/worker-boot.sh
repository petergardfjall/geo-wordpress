#!/bin/bash

set -e

sudo swapoff -a

sudo apt-get update && sudo apt-get install -y apt-transport-https curl
curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -
sudo apt-get update

#
# docker
#
sudo apt-get install -y docker.io
sudo tee /etc/docker/daemon.json <<EOF
{
  "exec-opts": ["native.cgroupdriver=systemd"],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m"
  },
  "storage-driver": "overlay2"
}
EOF
sudo mkdir -p /etc/systemd/system/docker.service.d
sudo systemctl daemon-reload
sudo systemctl restart docker

# NFS support
sudo apt-get install -y nfs-common

#
# kubernetes
#
sudo tee /etc/apt/sources.list.d/kubernetes.list <<EOF
deb https://apt.kubernetes.io/ kubernetes-xenial main
EOF
sudo apt-get update
sudo apt-get install -y kubelet=${k8s_version}-00 kubeadm=${k8s_version}-00 kubectl=${k8s_version}-00
sudo apt-mark hold kubelet kubeadm kubectl

sudo modprobe ip_vs
sudo modprobe ip_vs_rr
sudo modprobe ip_vs_wrr
sudo modprobe ip_vs_sh
sudo sysctl -p

sudo tee /etc/kubernetes/kubeadm.config <<EOF
apiVersion: kubeadm.k8s.io/v1alpha3
kind: JoinConfiguration
clusterName: "${cluster_name}"
discoveryTimeout: 5m0s
token: "${kubeadm_token}"
discoveryTokenAPIServers:
- ${master_private_ip}:6443
discoveryTokenUnsafeSkipCAVerification: true
nodeRegistration:
  kubeletExtraArgs:
    cgroup-driver:  systemd
    cloud-provider: gce
EOF

sudo kubeadm join --token="${kubeadm_token}" ${master_private_ip}:6443 --discovery-token-unsafe-skip-ca-verification | tee /home/ubuntu/kubeadm.log

echo "worker join: done"
