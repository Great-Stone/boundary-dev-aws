output "server_ip" {
  value = aws_instance.boundary.public_ip
}

output "boundary_addr" {
  value = "http://${aws_instance.boundary.public_ip}:9200"
}

output "boundary_org_admin" {
  value = boundary_account_password.admin.login_name
}

output "worker_ip" {
  value = aws_instance.boundary_worker.public_ip
}

output "target_ip" {
  value = aws_instance.internal[*].private_ip
}

output "rds_endpoint" {
  description = "RDS instance endpoint"
  value       = aws_db_instance.boundary.endpoint
}

output "rds_private" {
  value = data.aws_network_interface.rds.private_ip
}

output "rds_password" {
  value = nonsensitive(random_password.password.result)
}

/* output "boundary_access_key_id" {
    value = aws_iam_access_key.boundary.id
}

output "boundary_secret_access_key" {
  value = aws_iam_access_key.boundary.secret
  sensitive = true
} */