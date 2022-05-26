resource "boundary_scope" "org" {
  depends_on = [
    null_resource.boundary,
    aws_instance.boundary,
    module.vpc_1,
  ]

  scope_id    = "global"
  name        = "organization"
  description = "Organization scope"

  auto_create_admin_role   = false
  auto_create_default_role = false
}

resource "boundary_scope" "project" {
  name                     = "project"
  description              = "My first project"
  scope_id                 = boundary_scope.org.id
  auto_create_admin_role   = false
  auto_create_default_role = false
}

resource "boundary_auth_method" "password" {
  name        = "my_password_auth_method"
  description = "Password auth method"
  type        = "password"
  scope_id    = boundary_scope.org.id
}

resource "boundary_account_password" "admin" {
  name           = "admin"
  description    = "User account for my user"
  type           = "password"
  login_name     = "org-admin"
  password       = random_password.password.result
  auth_method_id = boundary_auth_method.password.id
}

resource "boundary_user" "admin" {
  name        = "admin"
  description = "My user!"
  account_ids = [boundary_account_password.admin.id]
  scope_id    = boundary_scope.org.id
}

resource "boundary_role" "global_anon_listing" {
  scope_id = "global"
  grant_strings = [
    "id=*;type=auth-method;actions=list,authenticate",
    "id=*;type=scope;actions=list,no-op",
    "id={{account.id}};actions=read,change-password"
  ]
  principal_ids = ["u_anon"]
}

resource "boundary_role" "org_anon_listing" {
  scope_id = boundary_scope.org.id
  grant_strings = [
    "id=*;type=auth-method;actions=list,authenticate",
    "type=scope;actions=list",
    "id={{account.id}};actions=read,change-password"
  ]
  principal_ids = ["u_anon"]
}

resource "boundary_role" "org_admin" {
  scope_id       = "global"
  grant_scope_id = boundary_scope.org.id
  grant_strings = [
    "id=*;type=*;actions=*"
  ]
  principal_ids = [boundary_user.admin.id]
}

resource "boundary_role" "project_admin" {
  scope_id       = boundary_scope.org.id
  grant_scope_id = boundary_scope.project.id
  grant_strings = [
    "id=*;type=*;actions=*"
  ]
  principal_ids = [boundary_user.admin.id]
}

# Add Host
resource "boundary_host_catalog_static" "static" {
  name     = "static"
  scope_id = boundary_scope.project.id
}

resource "boundary_host_static" "ec2" {
  count           = var.internal_server_count
  name            = "ec2_${count.index}"
  description     = "My host!"
  address         = aws_instance.internal[count.index].private_ip
  host_catalog_id = boundary_host_catalog_static.static.id
}

resource "boundary_host_set_static" "ec2" {
  name            = "ec2"
  host_catalog_id = boundary_host_catalog_static.static.id
  host_ids        = boundary_host_static.ec2[*].id
}

resource "boundary_host_static" "rds" {
  name            = "rds_postgre"
  description     = "My host!"
  address         = data.aws_network_interface.rds.private_ip
  host_catalog_id = boundary_host_catalog_static.static.id
}

resource "boundary_host_set_static" "rds" {
  name            = "rds"
  host_catalog_id = boundary_host_catalog_static.static.id
  host_ids        = [boundary_host_static.rds.id]
}

# Add Target SSH
resource "boundary_target" "ssh" {
  name          = "amazon_linux_ssh"
  description   = "Internal Target"
  type          = "tcp"
  default_port  = "22"
  scope_id      = boundary_scope.project.id
  worker_filter = "\"ap-northeast-2\" in \"/tags/region\""
  host_source_ids = [
    boundary_host_set_static.ec2.id
  ]
  /* application_credential_source_ids = [
    boundary_credential_library_vault.foo.id
  ] */
}

# Add Target Postgre RDS
resource "boundary_credential_store_vault" "rds" {
  name        = "vault_store"
  description = "My first Vault credential store!"
  address     = var.vault_addr
  token       = vault_token.boundary.client_token
  scope_id    = boundary_scope.project.id
  namespace   = "admin"
}

resource "boundary_credential_library_vault" "rds" {
  name                = "rds"
  description         = "My first Vault credential library!"
  credential_store_id = boundary_credential_store_vault.rds.id
  path                = "db/creds/test" # change to Vault backend path
  http_method         = "GET"
}

resource "boundary_target" "psql" {
  name                     = "rds_postgre"
  description              = "Internal Target"
  type                     = "tcp"
  default_port             = "5432"
  scope_id                 = boundary_scope.project.id
  worker_filter            = "\"ap-northeast-2\" in \"/tags/region\""
  session_connection_limit = -1
  host_source_ids = [
    boundary_host_set_static.rds.id
  ]
  application_credential_source_ids = [
    boundary_credential_library_vault.rds.id
  ]
}