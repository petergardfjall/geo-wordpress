#!/bin/bash

script=$(basename ${0})
bindir=$(dirname ${0})
assets_dir=$(realpath ${bindir}/../assets)

function log() {
    echo "[${script}] ${1}"
}

function die_with_error() {
    log "error: ${1}"
    exit 1
}

function print_usage() {
    echo "${script} [OPTIONS] CLUSTER0_NAME CLUSTER1_NAME CLUSTER2_NAME"
    echo
    echo "Deletes the Wordpress stack from each of the specified clusters."
    echo "Each CLUSTER_NAME is the name of a kubectl context."
    echo
    echo "Options:"
    echo "--assets-dir=DIR  Directory containing rendered templates."
    echo "                  Default: ${assets_dir}"
}

for arg in ${@}; do
    case ${arg} in
        --assets-dir=*)
            assets_dir=${arg/*=/}
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

if [[ $# -ne 3 ]]; then
    die_with_error "expected three kubectl cluster context names"
fi
cluster0=${1}
cluster1=${2}
cluster2=${3}

for c in ${cluster0} ${cluster1} ${cluster2}; do
    # validate clusters are in kubeconfig
    log "checking cluster availability ..."
    kubectl config use-context ${c}
    kubectl get nodes
done

log "cleaning up ${cluster0} ..."
kubectl config use-context ${cluster0}
kubectl delete -f ${assets_dir}/syncthing0.yaml
kubectl delete -f ${assets_dir}/wordpress.yaml
kubectl delete -f ${assets_dir}/pv.yaml
kubectl delete -f ${assets_dir}/nfs.yaml
kubectl delete -f ${assets_dir}/tidb0.yaml
kubectl delete -f ${assets_dir}/ns.yaml

log "cleaning up ${cluster1} ..."
kubectl config use-context ${cluster1}
kubectl delete -f ${assets_dir}/syncthing1.yaml
kubectl delete -f ${assets_dir}/wordpress.yaml
kubectl delete -f ${assets_dir}/pv.yaml
kubectl delete -f ${assets_dir}/nfs.yaml
kubectl delete -f ${assets_dir}/tidb1.yaml
kubectl delete -f ${assets_dir}/ns.yaml

log "cleaning up ${cluster2} ..."
kubectl config use-context ${cluster2}
kubectl delete -f ${assets_dir}/syncthing2.yaml
kubectl delete -f ${assets_dir}/wordpress.yaml
kubectl delete -f ${assets_dir}/pv.yaml
kubectl delete -f ${assets_dir}/nfs.yaml
kubectl delete -f ${assets_dir}/tidb2.yaml
kubectl delete -f ${assets_dir}/ns.yaml
