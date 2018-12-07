
variable "gce_project" {
  description = "The Google Cloud project under which to create the infrastructure."
}

variable "gce_credentials_path" {
  description = "The path toa file that contains your service account private key in JSON format. Download an existing/create a new service account for your project here: https://console.cloud.google.com/apis/credentials/serviceaccountkey"
}

variable "gce_region" {
  description = "Region where the infrastructure is to be created. For example, 'europe-west2'."
}

variable "cluster_name" {
  description = "Name of cluster. Used in kubeadm-generated kubeconfig."
}

variable "subnet_name" {
  description = "The name of the existing subnet in which cluster VMs are to be created."
}

#
# Optional variables
#

variable "master_vm_size" {
  description = "Size of VM."
  default     = "n1-standard-2"
}

variable "worker_vm_size" {
  description = "Size of VM."
  default     = "n1-standard-2"
}

variable "ssh_public_key_path" {
  description = "Local file path to public SSH login key for created VMs. Default: ~/.ssh/id_rsa.pub"
  default     = "~/.ssh/id_rsa.pub"
}

variable "ssh_private_key_path" {
  description = "Local file path to private SSH login key for created VMs. Default: ~/.ssh/id_rsa"
  default     = "~/.ssh/id_rsa"
}

variable "kubeadm_token" {
  default = "3lcnt0.lk1vmu7e1y9l8pxq"
}

#
# Resources
#

terraform {
  required_version = ">= 0.11.0"
}

provider "google" {
  version    = "~> 1.19"

  project     = "${var.gce_project}"
  credentials = "${file(pathexpand(var.gce_credentials_path))}"
  region      = "${var.gce_region}"
}

provider "null" {
  version    = "~> 1.0"
}


# read the credentials file and produces json fields in '${data.external.credentials.result}'.
# note: used to propagate service account credentials to created instances.
data "external" "credentials" {
  program = ["cat", "${pathexpand(var.gce_credentials_path)}"]
}


data "google_compute_subnetwork" "subnet" {
  name   = "${var.subnet_name}"
  region = "${var.gce_region}"
}

data "google_compute_zones" "region_zones" {
  region = "${var.gce_region}"
}

locals {
  # region zone in which to create VMs
  zone = "${data.google_compute_zones.region_zones.names[0]}"

  vm_username  = "ubuntu"
  ubuntu_image = "ubuntu-1604-lts"

  master_vm_name    = "${var.cluster_name}-master"
  master_private_ip = "${cidrhost(data.google_compute_subnetwork.subnet.ip_cidr_range, 10)}"

  worker_vm_name = "${var.cluster_name}-worker"
  worker_private_ip = "${cidrhost(data.google_compute_subnetwork.subnet.ip_cidr_range, 20)}"
}


#
# Master
#

# static IP
resource "google_compute_address" "master_static_ip" {
  name         = "${local.master_vm_name}-ip"
  address_type = "EXTERNAL"
}

resource "google_compute_instance" "master" {
  name         = "${local.master_vm_name}"
  machine_type = "${var.master_vm_size}"
  zone         = "${local.zone}"

  can_ip_forward = true

  # pass the service account we're running Terraform on to the created
  # instance to grant it rights to use Google Cloud APIs
  service_account {
    email  = "${data.external.credentials.result.client_email}"
    scopes = ["cloud-platform"]
  }

  # SSH login key
  metadata {
    sshKeys = "${local.vm_username}:${file(pathexpand(var.ssh_public_key_path))}"
  }

  boot_disk {
    auto_delete = "true"
    initialize_params {
      size  = "30"
      type  = "pd-ssd"
      image = "${local.ubuntu_image}"
    }
  }

  network_interface {
    subnetwork = "${data.google_compute_subnetwork.subnet.self_link}"
    network_ip = "${local.master_private_ip}"

    access_config {
      nat_ip = "${google_compute_address.master_static_ip.address}"
    }
  }


  tags = ["node", "master"]
}

data "template_file" "master_boot_sh" {
  template = "${file("${path.module}/master-boot.sh")}"

  vars {
    cluster_name      = "${var.cluster_name}"
    k8s_version       = "1.12.1"
    master_private_ip = "${local.master_private_ip}"
    master_public_ip  = "${google_compute_address.master_static_ip.address}"
    kubeadm_token     = "${var.kubeadm_token}"
  }
}

# Log onto VM and install kubernetes
resource "null_resource" "master_bootstrap" {
  depends_on = [
    "google_compute_instance.master",
    "google_compute_address.master_static_ip"
  ]

  connection {
    type        = "ssh"
    host        = "${google_compute_address.master_static_ip.address}"
    user        = "${local.vm_username}"
    agent       = "false"
    private_key = "${file(var.ssh_private_key_path)}"
    timeout     = "10m"
  }

  provisioner "remote-exec" {
    inline = <<EOF
${data.template_file.master_boot_sh.rendered}
EOF
  }
}


#
# Worker(s)
#

# static IP
resource "google_compute_address" "worker_static_ip" {
  name         = "${local.worker_vm_name}-ip"
  address_type = "EXTERNAL"
}

resource "google_compute_instance" "worker" {
  name         = "${local.worker_vm_name}"
  machine_type = "${var.worker_vm_size}"
  zone         = "${local.zone}"

  can_ip_forward = true

  # pass the service account we're running Terraform on to the created
  # instance to grant it rights to use Google Cloud APIs
  service_account {
    email  = "${data.external.credentials.result.client_email}"
    scopes = ["cloud-platform"]
  }

  # SSH login key
  metadata {
    sshKeys = "${local.vm_username}:${file(pathexpand(var.ssh_public_key_path))}"
  }

  boot_disk {
    auto_delete = "true"
    initialize_params {
      size  = "30"
      type  = "pd-ssd"
      image = "${local.ubuntu_image}"
    }
  }

  network_interface {
    subnetwork = "${data.google_compute_subnetwork.subnet.self_link}"
    network_ip = "${local.worker_private_ip}"

    access_config {
      nat_ip = "${google_compute_address.worker_static_ip.address}"
    }
  }

  tags = ["node", "worker"]
}

data "template_file" "worker_boot_sh" {
  template = "${file("${path.module}/worker-boot.sh")}"

  vars {
    cluster_name      = "${var.cluster_name}"
    k8s_version       = "1.12.1"
    master_private_ip = "${local.master_private_ip}"
    kubeadm_token     = "${var.kubeadm_token}"
  }
}

# Log onto VM and install kubernetes
resource "null_resource" "worker_bootstrap" {
  depends_on = [
    "google_compute_instance.worker",
    "google_compute_address.worker_static_ip"
  ]

  connection {
    type        = "ssh"
    host        = "${google_compute_address.worker_static_ip.address}"
    user        = "${local.vm_username}"
    agent       = "false"
    private_key = "${file(var.ssh_private_key_path)}"
    timeout     = "10m"
  }

  provisioner "remote-exec" {
    inline = <<EOF
${data.template_file.worker_boot_sh.rendered}
EOF
  }
}

resource "google_compute_instance_group" "workers" {
  name = "${local.worker_vm_name}-group"
  zone      = "${local.zone}"
  instances = [
    "${google_compute_instance.worker.self_link}"
  ]

  named_port {
    name = "wordpress"
    port = 30080
  }
}

#
# Output
#

output "master_boot_sh" {
  value = "${data.template_file.master_boot_sh.rendered}"
}

output "worker_instance_group" {
  value = "${google_compute_instance_group.workers.self_link}"
}

output "worker_boot_sh" {
  value = "${data.template_file.worker_boot_sh.rendered}"
}

output "master_public_ip" {
  value = "${google_compute_address.master_static_ip.address}"
}
output "worker_public_ip" {
  value = "${google_compute_address.worker_static_ip.address}"
}
