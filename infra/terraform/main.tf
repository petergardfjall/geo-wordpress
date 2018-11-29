#
# Sets up three kubernetes clusters with kubedm in three different GCE
# regions. A Google load-balancer is also set up to direct traffic between
# the sites.
#


variable "gce_project" {
  description = "The Google Cloud project under which to create the infrastructure."
}

variable "gce_credentials_path" {
  description = "The path to a file that contains your service account private key in JSON format. Download an existing/create a new service account for your project here: https://console.cloud.google.com/apis/credentials/serviceaccountkey"
}

variable "cluster0_region" {
  description = "Region where the first cluster is to be created. For example, 'europe-west2'."
}

variable "cluster1_region" {
  description = "Region where the second cluster is to be created. For example, 'europe-west2'."
}

variable "cluster2_region" {
  description = "Region where the third cluster is to be created. For example, 'europe-west2'."
}


variable "node_firewall_port_openings" {
  default     = ["22", "6443", "30800", "30080", "30084", "30160", "32379", "32380", "30400"]
}

variable "node_firewall_allowed_ips" {
  description = "A list of allowed source addresses for firewall openings. Specified as CIDR ranges (192.0.0.0/8)."
  default     = ["0.0.0.0/0"]
}

variable "cluster_name_prefix" {
  default = "geokube"
}


terraform {
  required_version = ">= 0.11.0"
}

provider "google" {
  version    = "~> 1.19"

  project     = "${var.gce_project}"
  credentials = "${file(pathexpand(var.gce_credentials_path))}"
}

#
# Resources
#

locals {
  network_name          = "${var.cluster_name_prefix}-net"
  cluster0_subnet_name  = "${var.cluster_name_prefix}-subnet-0"
  cluster1_subnet_name  = "${var.cluster_name_prefix}-subnet-1"
  cluster2_subnet_name  = "${var.cluster_name_prefix}-subnet-2"
  cluster0_subnet_cidr  = "10.1.0.0/16"
  cluster1_subnet_cidr  = "10.2.0.0/16"
  cluster2_subnet_cidr  = "10.3.0.0/16"

  node_firewall_name    = "${var.cluster_name_prefix}-node-firewall"
  cluster_firewall_name = "${var.cluster_name_prefix}-cluster-firewall"

  lb_name               = "${var.cluster_name_prefix}-lb"
}

#
# Network
#

resource "google_compute_network" "net" {
  name                    = "${local.network_name}"
  auto_create_subnetworks = "false"
  routing_mode            = "REGIONAL"
}

resource "google_compute_subnetwork" "cluster0_subnet" {
  name          = "${local.cluster0_subnet_name}"
  ip_cidr_range = "${local.cluster0_subnet_cidr}"
  region        = "${var.cluster0_region}"
  network       = "${google_compute_network.net.self_link}"
  private_ip_google_access = true
}

resource "google_compute_subnetwork" "cluster1_subnet" {
  name          = "${local.cluster1_subnet_name}"
  ip_cidr_range = "${local.cluster1_subnet_cidr}"
  region        = "${var.cluster1_region}"
  network       = "${google_compute_network.net.self_link}"
  private_ip_google_access = true
}

resource "google_compute_subnetwork" "cluster2_subnet" {
  name          = "${local.cluster2_subnet_name}"
  ip_cidr_range = "${local.cluster2_subnet_cidr}"
  region        = "${var.cluster2_region}"
  network       = "${google_compute_network.net.self_link}"
  private_ip_google_access = true
}


#
# Firewalls
#

# allow free inter-node communication
resource "google_compute_firewall" "cluster_firewall" {
  name    = "${local.cluster_firewall_name}"
  network = "${google_compute_network.net.name}"

  allow {
    protocol = "icmp"
  }
  allow {
    protocol = "tcp"
  }
  allow {
    protocol = "udp"
  }

  # rules will apply to instances matching these tags
  target_tags = ["node"]

  # rules will only apply to traffic originating from nodes in the cluster
  source_tags = ["node"]
}

# only allow incoming traffic to cluster nodes on the specified tcp ports
# and from the specified source IP ranges
resource "google_compute_firewall" "node_firewall" {
  name     = "${local.node_firewall_name}"
  network  = "${google_compute_network.net.name}"
  # make sure prio is higher (that is, lower value) than load-balancer's firewall
  priority = "100"
  allow {
    protocol = "tcp"
    ports    = "${var.node_firewall_port_openings}"
  }

  # rules will apply to instances matching these tags
  target_tags   = [ "node" ]
  source_ranges = "${var.node_firewall_allowed_ips}"
}






module "cluster_0" {
  source = "modules/gce"

  gce_project          = "${var.gce_project}"
  gce_credentials_path = "${var.gce_credentials_path}"
  gce_region           = "${var.cluster0_region}"
  cluster_name         = "${var.cluster_name_prefix}-${var.cluster0_region}"
  subnet_name          = "${google_compute_subnetwork.cluster0_subnet.name}"
}

module "cluster_1" {
  source = "modules/gce"

  gce_project          = "${var.gce_project}"
  gce_credentials_path = "${var.gce_credentials_path}"
  gce_region           = "${var.cluster1_region}"
  cluster_name         = "${var.cluster_name_prefix}-${var.cluster1_region}"
  subnet_name          = "${google_compute_subnetwork.cluster1_subnet.name}"
}

module "cluster_2" {
  source = "modules/gce"

  gce_project          = "${var.gce_project}"
  gce_credentials_path = "${var.gce_credentials_path}"
  gce_region           = "${var.cluster2_region}"
  cluster_name         = "${var.cluster_name_prefix}-${var.cluster2_region}"
  subnet_name          = "${google_compute_subnetwork.cluster2_subnet.name}"
}

#
# set up global Google load-balancer to reach nodeport services on nodes.
#

module "global_lb" {
  source            = "github.com/GoogleCloudPlatform/terraform-google-lb-http"
  name              = "${local.lb_name}"
  target_tags       = ["node"]
  firewall_networks = ["${google_compute_network.net.name}"]

  backends          = {
    "0" = [
      { group = "${module.cluster_0.worker_instance_group}" },
      { group = "${module.cluster_1.worker_instance_group}" },
      { group = "${module.cluster_2.worker_instance_group}" }
    ],
  }
  backend_params    = [
    # health check path, port name, port number, timeout seconds.
    "/license.txt,wordpress,30080,2"
  ]
}

#
# Output
#

output "cluster0_master_ip" {
  value = "${module.cluster_0.master_public_ip}"
}
output "cluster0_worker_ip" {
  value = "${module.cluster_0.worker_public_ip}"
}
output "cluster1_master_ip" {
  value = "${module.cluster_1.master_public_ip}"
}
output "cluster1_worker_ip" {
  value = "${module.cluster_1.worker_public_ip}"
}
output "cluster2_master_ip" {
  value = "${module.cluster_2.master_public_ip}"
}
output "cluster2_worker_ip" {
  value = "${module.cluster_2.worker_public_ip}"
}
output "loadbalancer_ip" {
  value = "${module.global_lb.external_ip}"
}
