# # # --------------------------------------------------------------------------------
# # # ------- Create GitLab repo -----------------------------------------------------
# # # --------------------------------------------------------------------------------

#create var with URL
#variable "url" {
#  type    = string
#  default = "https://gitlab.rebrainme.com/"
#}

#declare an empty variable here
#variable "token" {}

# Configure the GitLab Provider
#provider "gitlab" {
#  token    = var.token
#  base_url = var.url
#}

# Create project
#resource "gitlab_project" "OPS22" {
#  name             = "OPS22"
#  description      = "OPS22"
#  visibility_level = "private"
#}

# # # --------------------------------------------------------------------------------
# # # ------- Create vms at Digital Ocean--------------------------------------------- 
# # # --------------------------------------------------------------------------------

variable "do_token" {}

provider "digitalocean" {
  token = var.do_token
}

# create SSH key
resource "digitalocean_ssh_key" "key" {
  name       = "dobrizaSSH22"
  public_key = file("./ops22.pub")
}

variable "vm_names_proxy" {
  type        = list(string)
  default     = ["proxy0001"]
  description = "proxy vms for creation"

}

variable "vm_names_web" {
  type        = list(string)
  default     = ["web0001"]
  description = "proxy vms for creation"

}

# Create vms
resource "digitalocean_droplet" "vms_proxy" {
  count    = length(var.vm_names_proxy)
  image    = "debian-9-x64"
  ssh_keys = [digitalocean_ssh_key.key.id]
  name     = var.vm_names_proxy[count.index]
  size     = "s-1vcpu-1gb"
  region   = "nyc1"
  tags     = ["OPS22", "dobriza_yandex_ru"]
}

resource "digitalocean_droplet" "vms_web" {
  count    = length(var.vm_names_web)
  image    = "debian-9-x64"
  ssh_keys = [digitalocean_ssh_key.key.id]
  name     = var.vm_names_web[count.index]
  size     = "s-1vcpu-1gb"
  region   = "nyc1"
  tags     = ["OPS22", "dobriza_yandex_ru"]
}

# # # --------------------------------------------------------------------------------
# # # -------AWS Route53 configuration------------------------------------------------
# # # --------------------------------------------------------------------------------
# # # declare variables
variable "access_key" {}
variable "secret_key" {}

# Configure the AWS Provider
provider "aws" {
  version    = "~> 2.0"
  region     = "us-east-1"
  access_key = var.access_key
  secret_key = var.secret_key
}

#fetch data from route53
data "aws_route53_zone" "devops" {
  name = "devops.rebrain.srwx.net."
}

#create dns A record at devops.rebrain.srwx.net. zone
resource "aws_route53_record" "proxy" {
  zone_id = data.aws_route53_zone.devops.zone_id
  count   = length(digitalocean_droplet.vms_proxy)
  name    = digitalocean_droplet.vms_proxy[count.index].name
  type    = "A"
  ttl     = "300"
  records = [digitalocean_droplet.vms_proxy[count.index].ipv4_address]
}

resource "aws_route53_record" "web" {
  zone_id = data.aws_route53_zone.devops.zone_id
  count   = length(digitalocean_droplet.vms_web)
  name    = digitalocean_droplet.vms_web[count.index].name
  type    = "A"
  ttl     = "300"
  records = [digitalocean_droplet.vms_web[count.index].ipv4_address]
}

#--------------------------------------------------------------------------------------
# Building Ansible inventory file -----------------------------------------------------
#--------------------------------------------------------------------------------------
locals {
  proxyName   = aws_route53_record.proxy.*.name
  webName = aws_route53_record.web.*.name
  domainSuffix = data.aws_route53_zone.devops.name

}

resource "local_file" "inventory" {
  filename = "hosts.ini"
  content  = <<-EOT
[proxy]
%{for name in local.proxyName~}
${name}.${local.domainSuffix}
%{endfor~}

[web]
%{for name in local.webName~}
${name}.${local.domainSuffix}
%{endfor~}

[proxy:vars]
ansible_user = root
ansible_ssh_private_key_file = ../ops22

[web:vars]
ansible_user = root
ansible_ssh_private_key_file = ../ops22
  EOT
}

#--------------------------------------------------------------------------------------
# Run Ansible playbook on web servers -------------------------------------------------
#--------------------------------------------------------------------------------------

# resource "null_resource" "ansible_playbook_proxy" {
#   provisioner "remote-exec" {
#     inline = ["sudo apt install python"]

#     connection {
#       type        = "ssh"
#       user        = "root"
#       private_key = file("./ops22")
#       host        = digitalocean_droplet.vms[0].ipv4_address
#     }
#   }
#   provisioner "local-exec" {
#      command = "ansible-playbook install_nginx.yml -vv --vault-password-file vault_password"
#   }ы

# }

#--------------------------------------------------------------------------------------
# Configure local Environment Variables -----------------------------------------------
#--------------------------------------------------------------------------------------
resource "null_resource" "add_env" {

  provisioner "local-exec" {
     command = "export ANSIBLE_CONFIG=./ansible.cfg"
  }
}

# одрлро
