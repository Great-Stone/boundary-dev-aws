// vpc
resource "aws_vpc" "vpc_1" {
  cidr_block           = "10.1.0.0/16"
  enable_dns_hostnames = true

  tags = {
    "Name" = "vpc_1"
  }
}

// internet gateway
resource "aws_internet_gateway" "igw_1" {
  vpc_id = aws_vpc.vpc_1.id

  tags = {
    Name = "IGW_1"
  }
}

// EIP for NAT gw
resource "aws_eip" "nat_1" {
  vpc = true
}

// NAT gateway
resource "aws_nat_gateway" "nat_gw_1" {
  allocation_id = aws_eip.nat_1.id
  subnet_id     = aws_subnet.public_subnet_1.id
}

// public subnet
resource "aws_subnet" "public_subnet_1" {
  vpc_id                  = aws_vpc.vpc_1.id
  cidr_block              = "10.1.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name = "Public Subnet 1"
  }
}

// public route table
resource "aws_route_table" "public_rtb_1" {
  vpc_id = aws_vpc.vpc_1.id

  tags = {
    Name = "Public rtb 1"
  }
}

resource "aws_route" "public_rtb_1" {
  route_table_id         = aws_route_table.public_rtb_1.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.igw_1.id
}

resource "aws_route_table_association" "public_rtb_1" {
  subnet_id      = aws_subnet.public_subnet_1.id
  route_table_id = aws_route_table.public_rtb_1.id
}

// private subnets
resource "aws_subnet" "private_subnet_1" {
  vpc_id            = aws_vpc.vpc_1.id
  cidr_block        = "10.1.10.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]
  tags = {
    Name = "Private Subnet 1"
  }
}

// private route table
resource "aws_route_table" "private_rtb_1" {
  vpc_id = aws_vpc.vpc_1.id

  tags = {
    Name = "Private rtb"
  }
}

resource "aws_route" "private_rtb_1" {
  route_table_id         = aws_route_table.private_rtb_1.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat_gw_1.id
}

resource "aws_route_table_association" "private_rtb_1" {
  subnet_id      = aws_subnet.private_subnet_1.id
  route_table_id = aws_route_table.private_rtb_1.id
}

// Boundary
resource "aws_instance" "boundary_worker" {
  ami                    = "ami-081511b9e3af53902"
  instance_type          = "t3.micro"
  key_name               = aws_key_pair.example.key_name
  subnet_id              = aws_subnet.public_subnet_1.id
  vpc_security_group_ids = ["${aws_security_group.boundary_1.id}"]

  tags = {
    Name = "boundary"
  }

  depends_on = [aws_internet_gateway.igw]
}

resource "aws_security_group" "boundary_1" {
  name        = "boundary_1"
  description = "boundary_1"
  vpc_id      = aws_vpc.vpc_1.id
}

resource "aws_security_group_rule" "boundary_port_1" {
  type      = "ingress"
  from_port = 9201
  to_port   = 9203
  protocol  = "tcp"
  /* cidr_blocks       = [var.cidr_block] */
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.boundary_1.id
  description       = "boundary_1"
}

resource "aws_security_group_rule" "boundary_ssh_1" {
  type              = "ingress"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks       = ["${jsondecode(data.http.myip.body).ip}/32"]
  security_group_id = aws_security_group.boundary_1.id
  description       = "ssh"
}

resource "aws_security_group_rule" "websg_outbound_1" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.boundary_1.id
  description       = "outbound"
}

// Internal EC2
resource "aws_instance" "internal" {
  count                  = var.internal_server_count
  ami                    = "ami-081511b9e3af53902"
  instance_type          = "t3.micro"
  key_name               = aws_key_pair.example.key_name
  subnet_id              = aws_subnet.private_subnet_1.id
  vpc_security_group_ids = ["${aws_security_group.internalsg.id}"]

  tags = {
    Name        = "Internal"
    application = "boundary"
  }
}

resource "aws_security_group" "internalsg" {
  name        = "dbsg"
  description = "allow 22 from web"
  vpc_id      = aws_vpc.vpc_1.id
}

resource "aws_security_group_rule" "internalsg" {
  type                     = "ingress"
  from_port                = 22
  to_port                  = 22
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.boundary_1.id
  security_group_id        = aws_security_group.internalsg.id
  description              = "ssh"
}

resource "aws_security_group_rule" "outbound" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.internalsg.id
  description       = "outbound"
}

## Boundary Setup
data "template_file" "worker" {
  template = file("./template/install_worker.tpl")

  vars = {
    controller_ip     = aws_instance.boundary.public_ip
    worker_private_ip = aws_instance.boundary_worker.private_ip
    worker_public_ip  = aws_instance.boundary_worker.public_ip
  }
}

resource "null_resource" "boundary_worker" {
  depends_on = [
    postgresql_grant.privilige,
    null_resource.boundary
  ]

  triggers = {
    boundary_instance_id = aws_instance.boundary_worker.id
  }

  connection {
    host        = aws_instance.boundary_worker.public_ip
    type        = "ssh"
    user        = "ec2-user"
    private_key = file(".ssh/id_rsa")
  }

  provisioner "file" {
    content     = data.template_file.worker.rendered
    destination = "/tmp/setup.sh"
  }

  provisioner "remote-exec" {
    inline = [
      "sudo chmod 755 /tmp/setup.sh",
      "sudo /tmp/setup.sh"
    ]
  }
}
