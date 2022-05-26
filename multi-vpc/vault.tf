resource "vault_database_secrets_mount" "db" {
  path = "db"

  postgresql {
    name              = "postgres"
    username          = "postgres"
    password          = random_password.password.result
    connection_url    = "postgresql://{{username}}:{{password}}@${aws_db_instance.boundary.endpoint}/postgres"
    verify_connection = true
    allowed_roles = [
      "test",
    ]
  }
}

resource "vault_database_secret_backend_role" "test" {
  name    = "test"
  backend = vault_database_secrets_mount.db.path
  db_name = vault_database_secrets_mount.db.postgresql[0].name
  creation_statements = [
    "CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}';",
    "GRANT SELECT ON ALL TABLES IN SCHEMA public TO \"{{name}}\";",
  ]
}

resource "vault_token" "boundary" {
  no_default_policy = true
  policies          = ["super-user"]
  no_parent         = true
  renewable         = true
  period            = "20m"
}

/* resource "null_resource" "revoke" {
  depends_on = [
    vault_database_secret_backend_role.test
  ]
  provisioner "local-exec" {
    when    = destroy
    command = <<EOT
      VAULT_ADDR=${var.vault_addr}
      VAULT_NAMESPACE=admin
      VAULT_TOKEN=${vault_token.boundary.client_token}
      vault lease revoke -f -prefix db/creds/test
    EOT
  }
} */