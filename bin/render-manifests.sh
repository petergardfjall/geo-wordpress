#!/bin/bash

set -e

script=$(basename ${0})
bindir=$(dirname ${0})
assets_dir=$(realpath ${bindir}/../assets)
chart_dir=$(realpath ${bindir}/../manifests/helm)
values_yaml=$(realpath ${bindir}/../values.yaml)

function log() {
    echo "[${script}] ${1}"
}

function die_with_error() {
    echo "${1}"
    exit 1
}

function print_usage() {
    echo "${script} [OPTIONS]"
    echo
    echo "Renders Wordpress stack manifests for three Kubernetes clusters."
    echo "The manifests are rendered from the specified chart directory, "
    echo "filling in placeholders from the specified values.yaml file. Output "
    echo "is written to the given assets directory."
    echo
    echo "Options:"
    echo "--chart-dir=DIR   Chart templates directory."
    echo "                  Default: ${chart_dir}"
    echo "--assets-dir=DIR  Output directory for rendered templates."
    echo "                  Default: ${assets_dir}"
    echo "--values=PATH     Path to values.yaml."
    echo "                  Default: ${values_yaml}"
}

for arg in ${@}; do
    case ${arg} in
        --chart-dir=*)
            chart_dir=${arg/*=/}
            ;;
        --assets-dir=*)
            assets_dir=${arg/*=/}
            ;;
        --values=*)
            values_yaml=${arg/*=/}
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

log "writing manifests to ${assets_dir} ..."
mkdir -p ${assets_dir}
helm template ${chart_dir} --values ${values_yaml} -x templates/ns.yaml > ${assets_dir}/ns.yaml
helm template ${chart_dir} --values ${values_yaml} -x templates/tidb0.yaml > ${assets_dir}/tidb0.yaml
helm template ${chart_dir} --values ${values_yaml} -x templates/tidb1.yaml > ${assets_dir}/tidb1.yaml
helm template ${chart_dir} --values ${values_yaml} -x templates/tidb2.yaml > ${assets_dir}/tidb2.yaml
helm template ${chart_dir} --values ${values_yaml} -x templates/nfs.yaml > ${assets_dir}/nfs.yaml
helm template ${chart_dir} --values ${values_yaml} -x templates/pv.yaml > ${assets_dir}/pv.yaml
helm template ${chart_dir} --values ${values_yaml} -x templates/wordpress.yaml > ${assets_dir}/wordpress.yaml
helm template ${chart_dir} --values ${values_yaml} -x templates/syncthing0.yaml > ${assets_dir}/syncthing0.yaml
helm template ${chart_dir} --values ${values_yaml} -x templates/syncthing1.yaml > ${assets_dir}/syncthing1.yaml
helm template ${chart_dir} --values ${values_yaml} -x templates/syncthing2.yaml > ${assets_dir}/syncthing2.yaml
