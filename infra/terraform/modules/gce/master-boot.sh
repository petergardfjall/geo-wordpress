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

sudo tee /etc/apt/sources.list.d/kubernetes.list <<EOF
deb https://apt.kubernetes.io/ kubernetes-xenial main
EOF
sudo apt-get update
sudo apt-get install -y kubelet=${k8s_version}-00 kubeadm=${k8s_version}-00 kubectl=${k8s_version}-00
sudo apt-mark hold kubelet kubeadm kubectl

sudo modprobe br_netfilter && sudo sysctl -p
sudo sysctl net.bridge.bridge-nf-call-iptables=1
echo 1 | sudo tee /proc/sys/net/ipv4/ip_forward

sudo tee /etc/kubernetes/kubeadm.config <<EOF
apiVersion: kubeadm.k8s.io/v1alpha3
kind: InitConfiguration
bootstrapTokens:
- token: "${kubeadm_token}"
  ttl: "0s"
nodeRegistration:
  kubeletExtraArgs:
    cgroup-driver:  systemd
    cloud-provider: gce
apiEndpoint:
  advertiseAddress: "${master_private_ip}"
  bindPort:         6443
---
apiVersion: kubeadm.k8s.io/v1alpha3
kind: ClusterConfiguration
clusterName: "${cluster_name}"
kubernetesVersion: "v${k8s_version}"
apiServerCertSANs:
- "127.0.0.1"
- "${master_private_ip}"
- "${master_public_ip}"
networking:
  podSubnet:     "192.168.0.0/16"
  serviceSubnet: "10.96.0.0/12"
apiServerExtraArgs:
  cloud-provider: "gce"
controllerManagerExtraArgs:
  cluster-name:   "${cluster_name}"
  cloud-provider: "gce"
---
apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
address: 0.0.0.0
cgroupDriver: systemd
clusterDNS:
- 10.96.0.10
clusterDomain: "cluster.local"
staticPodPath: "/etc/kubernetes/manifests"
EOF

sudo kubeadm init --config=/etc/kubernetes/kubeadm.config | tee /home/ubuntu/kubeadm.log

# install kubectl for ubuntu user
[ -d /home/ubuntu/.kube ] || sudo mkdir -p /home/ubuntu/.kube
sudo cp /etc/kubernetes/admin.conf /home/ubuntu/.kube/config
sudo chown -R ubuntu:ubuntu /home/ubuntu/.kube/

# install a pod network
export KUBECONFIG=/home/ubuntu/.kube/config
curl -fsSL "https://docs.projectcalico.org/v3.1/getting-started/kubernetes/installation/hosted/rbac-kdd.yaml" -o /home/ubuntu/calico-rbac.yaml
curl -fsSL "https://docs.projectcalico.org/v3.1/getting-started/kubernetes/installation/hosted/kubernetes-datastore/calico-networking/1.7/calico.yaml" -o /home/ubuntu/calico.yaml
kubectl apply -f /home/ubuntu/calico-rbac.yaml
kubectl apply -f /home/ubuntu/calico.yaml

kubectl config view --flatten | sed "s/kubernetes/${cluster_name}/g" > /home/ubuntu/.kube/config.flat

kubectl completion bash >> /home/ubuntu/.bashrc
echo "master init: done"
