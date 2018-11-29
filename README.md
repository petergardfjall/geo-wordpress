This repository sets up a geo-distributed Wordpress installation running across
three Google Cloud regions. It is intended to showcase the feasibilty of using
NewSQL databases to build fault-tolerant systems.

*NOTE: the project is intended as an experiment, and is nowhere near ready for
production.*


Terraform is used to spawn three Kubernetes clusters in three separate Google
Cloud regions.

After this, Kubernetes manifests for a geo-wordpress stack are rendered and
deployed to the clusters. A separate geo-wordpress stack is run on each cluster
and it consists of:

- [TiDB](https://github.com/pingcap/tidb): a MySQL-compatible distributed database offering high availability and
  strong (ACID) consistency. TiDB operates in a distributed manner and uses the
  Raft protocol to agree on and order transactions. One instance is run in each
  region, meaning that the database can tolerate the loss of one region and
  still be able to form a quorum and, hence, remain available.
-
  [nfs-provisioner](https://github.com/kubernetes-incubator/external-storage/tree/master/nfs):
  A dynamic provisioner of NFS volumes for use by Wordpress pods.
- [Wordpress](https://hub.docker.com/_/wordpress/): Uses TiDB as a drop-in
  replacement for MySQL and mounts an NFS volume created by the nfs-provisioner.
- [SyncThing](https://syncthing.net/): forms a "file synchronization group" with
  the SyncThing processes on the other clusters and listens for filesystem
  notifications (inotify) on the Wordpress volume. Whenever a change is
  detected, the change is propagated to its peers. Think of it as a
  bidirectional rsync.

The whole setup is fronted by a global cloud load-balancer set up to spread
traffic across all regions. The load-balancer uses a health check to detect
failed nodes and, if detected, take that target out of rotation.

The setup is illustrated by the following image:

![architecture](/img/architecture.svg)



### Bring up Kubernetes clusters

0. Prepare a credentials file for GCE.
   You can fill out the `gce-secrets.var`.
   The parameters can be found in
   [infra/terraform/main.tf](infra/terraform/main.tf).

1. Add selected regions (and any additional variables) to `clusters.var`.

2. Bring up Kubernetes clusters in AWS, GCE, and Azure.
   Refer to [infra/terraform/main.tf](infra/terraform/main.tf) for all the
   variables.

        terraform init infra/terraform

        terraform apply --var-file gce-secrets.var --var-file clusters.var \
          infra/terraform

When terraform completes, note the ip address of the cloud load-balancer.



### Install the geo-wordpress stack onto the Kubernetes clusters
If Terraform finished successfully, just run:

     ./bin/install-wp-stack.sh

The script will (eventually) output a `kubeconfig` file which can be used to
communicate with the clusters using `kubectl`.

When it has been created, issue

    export KUBECONFIG=$PWD/kubeconfig

You can now wait for all pods to enter the `Running` state. In separate terminal
windows, issue the following commands:

	KUBECONFIG=/tmp/cluster0.config watch kubectl get pods -n wp
	KUBECONFIG=/tmp/cluster1.config watch kubectl get pods -n wp
	KUBECONFIG=/tmp/cluster2.config watch kubectl get pods -n wp


When everything is `Running`, navigate your web browser to
`http://$(terraform output loadbalancer_ip)`. This should take you to the
Wordpress installation page and your ready to go.


### Verify
You can verify that files are properly synchronized by, for instance, uploading
media and checking, for each cluster, that they have the same content in their
upload folder. For each cluster, run something like:

    watch kubectl exec -n wp wordpress-654b4dd45b-7j9fp -- ls -al /var/www/html/wp-content/uploads/2018/11


### Tear down clusters

Start by stopping instances and deleting the `geokube-*` created routes in
Google Cloud, since terraform will otherwise fail:

    gcloud compute instances list --filter="name~geokube" --format=json | jq -r .[].selfLink | xargs gcloud compute instances stop

    gcloud compute routes list --filter="name~geokube" --format=json | jq -r '.[].name' | xargs gcloud compute routes delete --quiet


Then run:

    terraform destroy --force --var-file gce-secrets.var --var-file clusters.var infra/terraform
