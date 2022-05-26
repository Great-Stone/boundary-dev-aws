variable "default_tags" {
  type = map(any)
  default = {
    purpose   = "boundary dev"
    ttl       = 72
    terraform = true
  }
}

variable "prefix" {
  default = "test"
}

variable "rds_username" {
  default = "postgres"
}

variable "internal_server_count" {
  default = 1
}

variable "vault_addr" {
  default = "https://gs-cluster.vault.50dc8a23-a8c8-4982-8053-6ba3cf2f254f.aws.hashicorp.cloud:8200"
}