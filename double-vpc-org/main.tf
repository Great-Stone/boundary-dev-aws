terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
    postgresql = {
      source  = "cyrilgdn/postgresql"
      version = "~> 1.0"
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

provider "postgresql" {
  host            = aws_db_instance.boundary.address
  port            = 5432
  database        = "postgres"
  username        = var.rds_username
  password        = random_password.password.result
  sslmode         = "require"
  connect_timeout = 5
  superuser       = false
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

data "aws_availability_zones" "available" {
  state = "available"
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