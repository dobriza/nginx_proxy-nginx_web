## # # ------------------------------------------------------------------------------------------------
## # # ------- Create GitLab repo ---------------------------------------------------------------------
## # # ------------------------------------------------------------------------------------------------



##create var with URL

#variable "url" {
#  type    = string
#  default = "https://gitlab.rebrainme.com/"
#}
#
##declare an empty variable here

#variable "token" {}
#
## Configure the GitLab Provider

#provider "gitlab" {
#  token    = var.token
#  base_url = var.url
#}
#
## Create project

#resource "gitlab_project" "OPS22" {
#  name             = "OPS22"
#  description      = "OPS22"
#  visibility_level = "private"
#}




# # # -------------------------------------------------------------------------------------------------
# # # ------- Create vms at Digital Ocean--------------------------------------------------------------
# # # -------------------------------------------------------------------------------------------------



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
  default     = ["proxy0020"]
  description = "proxy vms for creation"

}

variable "vm_names_web" {
  type        = list(string)
  default     = ["web0020"]
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



# # # --------------------------------------------------------------------------------------------------
# # # -------AWS Route53 configuration------------------------------------------------------------------
# # # --------------------------------------------------------------------------------------------------



# Declare variables that stores keys 

variable "access_key" {}
variable "secret_key" {}

# Configure the AWS Provider

provider "aws" {
  version    = "~> 2.0"
  region     = "us-east-1"
  access_key = var.access_key
  secret_key = var.secret_key
}

# Fetch data from route53

data "aws_route53_zone" "devops" {
  name = "devops.rebrain.srwx.net."
}

# Create DNS A records at devops.rebrain.srwx.net. zone

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



#-------------------------------------------------------------------------------------------------------
# Building Ansible inventory file at working directory -------------------------------------------------
#-------------------------------------------------------------------------------------------------------

# Declare local variables for building a loop over resources that Terraform has created.

locals {
  proxyName    = aws_route53_record.proxy.*.name
  webName      = aws_route53_record.web.*.name
  domainSuffix = data.aws_route53_zone.devops.name

}


# Add new line to inventory file in loop

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
ansible_ssh_private_key_file = ./ops22

[web:vars]
ansible_user = root
ansible_ssh_private_key_file = ./ops22
  EOT
}


#-------------------------------------------------------------------------------------------------------
# Building main.yml file for configuring virtual server within proxy role. 
#-------------------------------------------------------------------------------------------------------


# Creating main.yml file. Building a loop over resources that Terraform has created.

resource "local_file" "defaults_file" {
  depends_on = [local_file.inventory]
  filename   = "main.yml"
  content    = <<-EOT
sites_config_template_directory: ../templates
site1_Parent_Directory: ../files/custom_site
nginxPortNumber: 80
email: dobriza@yandex.ru
%{for name in local.proxyName~}
proxy_name: ${name}.${local.domainSuffix}
%{endfor~}
%{for name in local.webName~}
web_name: ${name}.${local.domainSuffix}
%{endfor~}
  EOT

  # Run local provisioner to copy main.yml file from working directory 
  # to target directory: ./roles/nginx_proxy/defaults/   


  provisioner "local-exec" {
    command = "cp -rp ./main.yml ./roles/nginx_proxy/defaults/ && rm ./main.yml"
  }
}



#------------------------------------------------------------------------------------------------------
# Run Ansible role on a web server --------------------------------------------------------------------
#------------------------------------------------------------------------------------------------------


# You can use remote-exec provisioner that will wait until the connection to the instance is established# and then invoke the local-exec provisioner to run Ansible playbook.

resource "null_resource" "ansible_playbook_run_web" {
  count      = length(var.vm_names_web)
  depends_on = [local_file.defaults_file]
  provisioner "remote-exec" {

    connection {
      type        = "ssh"
      user        = "root"
      private_key = file("./ops22")
      host        = digitalocean_droplet.vms_web[count.index].ipv4_address
    }
  }
  provisioner "local-exec" {
    command = "export ANSIBLE_CONFIG=./ansible.cfg && time ansible-playbook install_nginx.yml -vv --vault-password-file vault_pass"
  }
}



#-------------------------------------------------------------------------------------
# Run Ansible role on a proxy server -------------------------------------------------
#-------------------------------------------------------------------------------------



# You can use remote-exec provisioner that will wait until the connection to the instance is established# and then invoke the local-exec provisioner to run Ansible playbook.

resource "null_resource" "ansible_playbook_run_proxy" {
  count      = length(var.vm_names_proxy)
  depends_on = [null_resource.ansible_playbook_run_web]
  provisioner "remote-exec" {

    connection {
      type        = "ssh"
      user        = "root"
      private_key = file("./ops22")
      host        = digitalocean_droplet.vms_proxy[count.index].ipv4_address
    }
  }
  provisioner "local-exec" {
    command = "export ANSIBLE_CONFIG=./ansible.cfg && time ansible-playbook install_nginx_proxy.yml -vv --vault-password-file vault_pass"
  }
}

