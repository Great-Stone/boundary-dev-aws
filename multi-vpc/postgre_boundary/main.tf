terraform {
  required_providers {
    postgresql = {
      source  = "cyrilgdn/postgresql"
      version = "~> 1.0"
    }
  }
}

provider "postgresql" {
  host            = var.address
  port            = 5432
  database        = "postgres"
  username        = var.username
  password        = var.password
  sslmode         = "require"
  connect_timeout = 5
  superuser       = false
}

# Boundary Postgres
## CREATE ROLE boundary WITH LOGIN PASSWORD 'PASSWORD';
resource "postgresql_role" "boundary" {
  name     = "boundary"
  login    = true
  password = "boundary"
}

## CREATE DATABASE boundary OWNER boundary;
resource "postgresql_database" "boundary" {
  name  = "boundary"
  owner = postgresql_role.boundary.name
}

## GRANT ALL PRIVILEGES ON DATABASE boundary TO boundary;
resource "postgresql_grant" "privilige" {
  database    = postgresql_database.boundary.name
  role        = postgresql_role.boundary.name
  schema      = "public"
  object_type = "database"
  privileges  = ["ALL"]
}