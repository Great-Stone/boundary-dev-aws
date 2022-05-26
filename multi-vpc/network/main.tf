locals {
  cidr_list = split(".", var.cidr_block)
}

resource "aws_vpc" "vpc" {
  cidr_block           = var.cidr_block
  enable_dns_hostnames = true
}

data "aws_availability_zones" "available" {
  state = "available"
}

// internet gateway
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.vpc.id

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
  vpc_id                  = aws_vpc.vpc.id
  cidr_block              = "${local.cidr_list[0]}.${local.cidr_list[1]}.${count.index}.0/24"
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "Public Subnet"
  }
}

// public route table
resource "aws_route_table" "public_rtb" {
  vpc_id = aws_vpc.vpc.id
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
  default_network_acl_id = aws_vpc.vpc.default_network_acl_id

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

// private subnets
resource "aws_subnet" "private_subnet" {
  vpc_id            = aws_vpc.vpc.id
  cidr_block        = "${local.cidr_list[0]}.${local.cidr_list[1]}.100.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]
}

// private route table
resource "aws_route_table" "private_rtb" {
  vpc_id = aws_vpc.vpc.id
}

resource "aws_route" "private_rtb" {
  route_table_id         = aws_route_table.private_rtb.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat_gw[0].id
}

resource "aws_route_table_association" "private_rtb" {
  subnet_id      = aws_subnet.private_subnet.id
  route_table_id = aws_route_table.private_rtb.id
}

// security_group
resource "aws_security_group" "boundary" {
  description = "boundary"
  vpc_id      = aws_vpc.vpc.id
}

resource "aws_security_group_rule" "boundary_port" {
  type        = "ingress"
  from_port   = var.public_from_port
  to_port     = var.public_to_port
  protocol    = "tcp"
  cidr_blocks = ["0.0.0.0/0"]
  /* cidr_blocks       = ["${jsondecode(data.http.myip.body).ip}/32"] // , aws_vpc.vpc_1.cidr_block] */
  security_group_id = aws_security_group.boundary.id
  description       = "boundary"
}

resource "aws_security_group_rule" "outbound" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.boundary.id
  description       = "outbound"
}

resource "aws_security_group" "ssh" {
  description = "boundary"
  vpc_id      = aws_vpc.vpc.id
}

resource "aws_security_group_rule" "ssh" {
  type              = "ingress"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks       = [var.myip_cidr]
  security_group_id = aws_security_group.ssh.id
  description       = "ssh"
}
