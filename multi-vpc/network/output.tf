output "vpc" {
  value = aws_vpc.vpc
}

output "route_table_public_id" {
  value = aws_route_table.public_rtb.id
}

output "public_subnets" {
  value = aws_subnet.public_subnet
}

output "private_subnet" {
  value = aws_subnet.private_subnet
}

output "security_group_id_boundary" {
  value = aws_security_group.boundary.id
}

output "security_group_id_ssh" {
  value = aws_security_group.ssh.id
}