// vpc
resource "aws_vpc" "vpc_0" {
  cidr_block           = "10.10.0.0/16"
  enable_dns_hostnames = true

  tags = {
    "Name" = "vpc_0"
  }
}

// Peering
resource "aws_vpc_peering_connection" "boundary" {
  peer_vpc_id = aws_vpc.vpc_0.id
  vpc_id      = aws_vpc.vpc_1.id
  auto_accept = true

  tags = {
    Name = "VPC Peering between Boundary"
  }
}

resource "aws_route" "owner" {
  route_table_id            = aws_route_table.public_rtb.id
  destination_cidr_block    = aws_vpc.vpc_1.cidr_block
  vpc_peering_connection_id = aws_vpc_peering_connection.boundary.id
}

resource "aws_route" "accepter" {
  route_table_id            = aws_route_table.public_rtb_1.id
  destination_cidr_block    = aws_vpc.vpc_0.cidr_block
  vpc_peering_connection_id = aws_vpc_peering_connection.boundary.id
}

// internet gateway
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.vpc_0.id

  tags = {
    Name = "IGW"
  }
}

// EIP for NAT gw
resource "aws_eip" "nat" {
  count = 2
  vpc   = true
}

// NAT gateway
resource "aws_nat_gateway" "nat_gw" {
  count         = 2
  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public_subnet[count.index].id
}

// public subnet
resource "aws_subnet" "public_subnet" {
  count                   = 2
  vpc_id                  = aws_vpc.vpc_0.id
  cidr_block              = "10.10.${count.index}.0/24"
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "Public Subnet"
  }
}

// public route table
resource "aws_route_table" "public_rtb" {
  vpc_id = aws_vpc.vpc_0.id

  tags = {
    Name = "Public rtb"
  }
}

resource "aws_route" "public_rtb" {
  route_table_id         = aws_route_table.public_rtb.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.igw.id
}

resource "aws_route_table_association" "public_rtb" {
  count          = 2
  subnet_id      = aws_subnet.public_subnet[count.index].id
  route_table_id = aws_route_table.public_rtb.id
}

resource "aws_default_network_acl" "example" {
  default_network_acl_id = aws_vpc.vpc_0.default_network_acl_id

  egress {
    protocol   = "tcp"
    rule_no    = 100
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 65535
  }

  ingress {
    protocol   = "-1"
    rule_no    = 100
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }
}

// Boundary Controller
resource "aws_instance" "boundary" {
  ami                    = "ami-081511b9e3af53902"
  instance_type          = "t3.micro"
  key_name               = aws_key_pair.example.key_name
  subnet_id              = aws_subnet.public_subnet[0].id
  vpc_security_group_ids = ["${aws_security_group.boundary.id}"]
  /* user_data              = data.template_file.controller.rendered */

  tags = {
    Name = "boundary"
  }

  depends_on = [aws_internet_gateway.igw]
}

resource "aws_security_group" "boundary" {
  name        = "boundary"
  description = "boundary"
  vpc_id      = aws_vpc.vpc_0.id
}

resource "aws_security_group_rule" "boundary_port" {
  type        = "ingress"
  from_port   = 9200
  to_port     = 9203
  protocol    = "tcp"
  cidr_blocks = ["0.0.0.0/0"]
  /* cidr_blocks       = ["${jsondecode(data.http.myip.body).ip}/32"] // , aws_vpc.vpc_1.cidr_block] */
  security_group_id = aws_security_group.boundary.id
  description       = "boundary"
}

resource "aws_security_group_rule" "boundary_ssh" {
  type              = "ingress"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks       = ["${jsondecode(data.http.myip.body).ip}/32"] // , aws_vpc.vpc_1.cidr_block]
  security_group_id = aws_security_group.boundary.id
  description       = "http"
}

resource "aws_security_group_rule" "boundary_outbound" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.boundary.id
  description       = "outbound"
}

## RDS 구성
resource "aws_security_group" "rds" {
  name   = "postgresql_rds"
  vpc_id = aws_vpc.vpc_0.id

  tags = {
    Name = "boundary_rds"
  }
}

resource "aws_security_group_rule" "rds_port" {
  type      = "ingress"
  from_port = 5432
  to_port   = 5432
  protocol  = "tcp"
  /* cidr_blocks = ["0.0.0.0/0"] */
  cidr_blocks       = ["${jsondecode(data.http.myip.body).ip}/32", aws_vpc.vpc_0.cidr_block, aws_vpc.vpc_1.cidr_block, "0.0.0.0/0"]
  security_group_id = aws_security_group.rds.id
  description       = "boundary"
}

resource "aws_security_group_rule" "rds_outbound" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.rds.id
  description       = "outbound"
}

resource "aws_db_subnet_group" "example" {
  name       = "example"
  subnet_ids = [aws_subnet.public_subnet[0].id, aws_subnet.public_subnet[1].id]
}

resource "aws_db_parameter_group" "example" {
  name   = "example"
  family = "postgres13"

  parameter {
    name  = "log_connections"
    value = "1"
  }
}

resource "random_password" "password" {
  length  = 16
  special = false
}

resource "aws_db_instance" "boundary" {
  identifier             = "example"
  instance_class         = "db.t3.micro"
  allocated_storage      = 5
  engine                 = "postgres"
  engine_version         = "13.6"
  username               = var.rds_username
  password               = random_password.password.result
  db_subnet_group_name   = aws_db_subnet_group.example.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  parameter_group_name   = aws_db_parameter_group.example.name
  publicly_accessible    = true
  skip_final_snapshot    = true
}

data "aws_network_interface" "rds" {
  filter {
    name   = "subnet-id"
    values = [aws_subnet.public_subnet[0].id, aws_subnet.public_subnet[1].id]
  }
  filter {
    name   = "description"
    values = ["RDSNetworkInterface"]

  }
  depends_on = [aws_db_instance.boundary]
}

# Boundary Postgres
## CREATE ROLE boundary WITH LOGIN PASSWORD 'PASSWORD';
resource "postgresql_role" "boundary" {
  depends_on = [
    aws_security_group_rule.rds_port,
    aws_db_instance.boundary
  ]

  name     = "boundary"
  login    = true
  password = "boundary"
}

## CREATE DATABASE boundary OWNER boundary;
resource "postgresql_database" "boundary" {
  depends_on = [
    aws_security_group_rule.rds_port,
    aws_db_instance.boundary
  ]

  name  = "boundary"
  owner = postgresql_role.boundary.name
}

## GRANT ALL PRIVILEGES ON DATABASE boundary TO boundary;
resource "postgresql_grant" "privilige" {
  depends_on = [
    aws_security_group_rule.rds_port,
    aws_db_instance.boundary
  ]

  database    = postgresql_database.boundary.name
  role        = postgresql_role.boundary.name
  schema      = "public"
  object_type = "database"
  privileges  = ["ALL"]
}

## Boundary Setup
data "template_file" "controller" {
  template = file("./template/install_controller.tpl")

  vars = {
    controller_public_ip  = aws_instance.boundary.public_ip
    controller_private_ip = aws_instance.boundary.private_ip
    postgresql_ip         = data.aws_network_interface.rds.private_ip
    postgresql_port       = aws_db_instance.boundary.port
    postgresql_username   = aws_db_instance.boundary.username
    postgresql_password   = aws_db_instance.boundary.password
  }
}

resource "null_resource" "boundary" {
  depends_on = [
    postgresql_grant.privilige
  ]

  triggers = {
    boundary_instance_id = aws_instance.boundary.id
  }

  connection {
    host        = aws_instance.boundary.public_ip
    type        = "ssh"
    user        = "ec2-user"
    private_key = file(".ssh/id_rsa")
  }

  provisioner "file" {
    content     = data.template_file.controller.rendered
    destination = "/tmp/setup.sh"
  }

  provisioner "remote-exec" {
    inline = [
      "sudo chmod 755 /tmp/setup.sh",
      "sudo /tmp/setup.sh",
      "sleep 10"
    ]
  }
}