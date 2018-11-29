#!/bin/bash

#
# Renders a values.yaml file for a multi-cluster brought up via Terraform.
# The script is assumed to be called from the directory holding the Terraform
# state .
#

script=$(basename ${0})
bindir=$(dirname ${0})
terraform_state=$(realpath ${bindir}/../terraform.tfstate)

function die_with_error() {
    echo "${1}"
    exit 1
}

function print_usage() {
    echo "${script} [OPTIONS]"
    echo
    echo "Renders a values.yaml file for a geo-wordpress helm chart from values"
    echo "received from Terraform output."
    echo
    echo "Options:"
    echo "--terraform-state=PATH  Path to terraform.tfstate file."
    echo "                        Default: ${terraform_state}"
}

for arg in ${@}; do
    case ${arg} in
        --terraform-state=*)
            terraform_state=${arg/*=/}
            ;;
        --help)
            print_usage
	    exit 0
            ;;
        --*)
            die_with_error "unrecognized option: ${arg}"
            ;;
        *)
            # no option, assume only positional arguments left
            break
            ;;
    esac
    shift
done


cluster0_node_ip=$(terraform output --state ${terraform_state} cluster0_master_ip)
cluster1_node_ip=$(terraform output --state ${terraform_state} cluster1_master_ip)
cluster2_node_ip=$(terraform output --state ${terraform_state} cluster2_master_ip)

cat > values.yaml <<EOF
namespace: wp

pd:
  image: pingcap/pd:v2.0.9
  ips:
  - ${cluster0_node_ip}
  - ${cluster1_node_ip}
  - ${cluster2_node_ip}
  clientNodePort: 32379
  peerNodePort: 32380

tikv:
  image: pingcap/tikv:v2.0.9
  ips:
  - ${cluster0_node_ip}
  - ${cluster1_node_ip}
  - ${cluster2_node_ip}
  nodePort: 30160

tidb:
  image: pingcap/tidb:v2.0.9
  ips:
  - ${cluster0_node_ip}
  - ${cluster1_node_ip}
  - ${cluster2_node_ip}
  mysqlNodePort: 30400

wordpress:
  image: wordpress:4.9
  nodePort: 30080

nfs:
  image: quay.io/kubernetes_incubator/nfs-provisioner:v2.2.0-k8s1.12
  provisionerName: elastisys.com/nfs
  # the IP address (within the clusters service IP range) to assign to the NFS
  # service (this is needed since NFS volumes cannot refer to a service
  # hostname, but needs to use an IP)
  serviceIP: 10.96.0.2

syncthing:
  image: linuxserver/syncthing:142
  ips:
  - ${cluster0_node_ip}
  - ${cluster1_node_ip}
  - ${cluster2_node_ip}
  peerNodePort: 30084
  uiNodePort: 30800
EOF
