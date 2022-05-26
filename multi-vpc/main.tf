terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
    boundary = {
      source  = "hashicorp/boundary"
      version = "~> 1.0"
    }
    vault = {
      source  = "hashicorp/vault"
      version = "~> 3.0"
    }
  }
}

provider "aws" {
  region = "ap-northeast-2"
  default_tags {
    tags = var.default_tags
  }
}

provider "boundary" {
  addr             = "http://${aws_instance.boundary.public_ip}:9200"
  recovery_kms_hcl = <<EOT
kms "aead" {
  purpose   = "recovery"
  aead_type = "aes-gcm"
  key       = "8fZBjCUfN0TzjEGLQldGY4+iE9AkOvCfjh7+p0GtRBQ="
  key_id    = "global_recovery"
}
EOT
}

variable "login_username" {
  default = "boundary"
}
variable "login_password" {}

provider "vault" {
  address   = var.vault_addr
  namespace = "admin"

  auth_login {
    namespace = "admin"
    path      = "auth/userpass-boundary/login/${var.login_username}"

    parameters = {
      password = var.login_password
    }
  }
}

resource "aws_key_pair" "example" {
  key_name   = "${var.prefix}-key-pair"
  public_key = file(".ssh/id_rsa.pub")
}

data "http" "myip" {
  url = "https://api.myip.com"

  request_headers = {
    Accept = "application/json"
  }
}

module "vpc_1" {
  source = "./network"

  cidr_block       = "10.10.0.0/16"
  public_from_port = 9200
  public_to_port   = 9203
  myip_cidr        = "${jsondecode(data.http.myip.body).ip}/32"
}

module "vpc_2" {
  source = "./network"

  cidr_block       = "10.20.0.0/16"
  public_from_port = 9201
  public_to_port   = 9203
  myip_cidr        = "${jsondecode(data.http.myip.body).ip}/32"
}

// Peering
resource "aws_vpc_peering_connection" "boundary" {
  peer_vpc_id = module.vpc_1.vpc.id
  vpc_id      = module.vpc_2.vpc.id
  auto_accept = true

  tags = {
    Name = "VPC Peering between Boundary"
  }
}

resource "aws_route" "owner" {
  route_table_id            = module.vpc_1.route_table_public_id
  destination_cidr_block    = module.vpc_2.vpc.cidr_block
  vpc_peering_connection_id = aws_vpc_peering_connection.boundary.id
}

resource "aws_route" "accepter" {
  route_table_id            = module.vpc_2.route_table_public_id
  destination_cidr_block    = module.vpc_1.vpc.cidr_block
  vpc_peering_connection_id = aws_vpc_peering_connection.boundary.id
}
