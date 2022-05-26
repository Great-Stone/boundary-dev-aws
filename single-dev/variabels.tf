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

variable "cidr_block" {
  default = "0.0.0.0/0"
}