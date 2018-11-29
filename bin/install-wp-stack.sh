#!/bin/bash

#
# This script renders the Kubernetes manifests for the Wordpress stack and
# deploys it onto all clusters. The script assumes that Terraform has already
# been run successfully and brought up Kubernetes clusters in three Google
# Cloud regions.
#

set -e

script=$(basename ${0})
bindir=$(dirname ${0})
terraform_state=$(realpath ${bindir}/../terraform.tfstate)
chart_dir=$(realpath ${bindir}/../manifests/helm)
assets_dir=./assets

function die_with_error() {
    echo "${1}"
    exit 1
}

function print_usage() {
    echo "${script} [OPTIONS]"
    echo
    echo "Renders the Kubernetes manifests for the geo-wordpress stack and "
    echo "deploys it onto all clusters. The script assumes that Terraform has"
    echo "already been run successfully and brought up Kubernetes clusters in "
    echo "three Google Cloud regions. The script will write a kubectl config"
    echo "file named 'kubeconfig' to the current directory."
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


# download kubeconfig file from each cluster
for cluster in cluster0 cluster1 cluster2; do
    master_ip=$(terraform output --state ${terraform_state} ${cluster}_master_ip)
    scp -o StrictHostKeyChecking=no -i ~/.ssh/id_rsa ubuntu@${master_ip}:~/.kube/config /tmp/${cluster}.config
    # replace private ip with public ip
    sed -i "s#server:.*#server: https://${master_ip}:6443#g" /tmp/${cluster}.config
    # rename context
    sed -i "s#kubernetes-admin#${cluster}-adm#g" /tmp/${cluster}.config
done

# merge kubecfonigs
export KUBECONFIG=/tmp/cluster0.config:/tmp/cluster1.config:/tmp/cluster2.config
kubectl config view --flatten --merge > kubeconfig
export KUBECONFIG=${PWD}/kubeconfig

# render geo-wordpress kubernetes manifests
rm -rf ${assets_dir}
${bindir}/render-values.sh
${bindir}/render-manifests.sh --chart-dir=${chart_dir} --values=./values.yaml --assets-dir=${assets_dir}

# apply geo-wordpress kubernetes manifests
kubectxs=$(egrep 'name:.*@' kubeconfig | awk '{print $2}')
${bindir}/deploy-manifests.sh --assets-dir=${assets_dir} ${kubectxs}
