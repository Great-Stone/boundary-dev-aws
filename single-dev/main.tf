terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
      version = "~> 4.0"
    }
  }
}

provider "aws" {
  region = "ap-northeast-2"
  default_tags {
    tags = var.default_tags
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}

// vpc
resource "aws_vpc" "vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true

  tags = {
    "Name" = "vpc"
  }
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
  vpc = true
}

// NAT gateway
resource "aws_nat_gateway" "nat_gw" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public_subnet.id
}

// public subnet
resource "aws_subnet" "public_subnet" {
  vpc_id                  = aws_vpc.vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name = "Public Subnet"
  }
}

// public route table
resource "aws_route_table" "public_rtb" {
  vpc_id = aws_vpc.vpc.id

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
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public_rtb.id
}

// private subnets
resource "aws_subnet" "private_subnet" {
  vpc_id            = aws_vpc.vpc.id
  cidr_block        = "10.0.10.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]
  tags = {
    Name = "Private Subnet"
  }
}

// private route table
resource "aws_route_table" "private_rtb" {
  vpc_id = aws_vpc.vpc.id

  tags = {
    Name = "Private rtb"
  }
}

resource "aws_route" "private_rtb" {
  route_table_id         = aws_route_table.private_rtb.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat_gw.id
}

resource "aws_route_table_association" "private_rtb" {
  subnet_id      = aws_subnet.private_subnet.id
  route_table_id = aws_route_table.private_rtb.id
}

resource "aws_key_pair" "example" {
  key_name   = "${var.prefix}-key-pair"
  public_key = file(".ssh/id_rsa.pub")
}

// Boundary
resource "aws_instance" "boundary" {
  ami                    = "ami-081511b9e3af53902"
  instance_type          = "t3.micro"
  key_name               = aws_key_pair.example.key_name
  subnet_id              = aws_subnet.public_subnet.id
  vpc_security_group_ids = ["${aws_security_group.boundary.id}"]
  user_data              = <<-EOF
                           #!/bin/bash
                           sudo yum update -y
                           sudo yum install -y yum-utils
                           sudo amazon-linux-extras install docker -y
                           sudo service docker start
                           sudo systemctl enable docker
                           sudo usermod -a -G docker ec2-user
                           sudo yum-config-manager --add-repo https://rpm.releases.hashicorp.com/AmazonLinux/hashicorp.repo
                           sudo yum -y install boundary
                           EOF

  tags = {
    Name = "boundary"
  }

  depends_on = [aws_internet_gateway.igw]
}

resource "aws_security_group" "boundary" {
  name        = "boundary"
  description = "boundary"
  vpc_id      = aws_vpc.vpc.id
}

resource "aws_security_group_rule" "boundary_port" {
  type              = "ingress"
  from_port         = 9200
  to_port           = 9203
  protocol          = "tcp"
  /* cidr_blocks       = [var.cidr_block] */
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.boundary.id
  description       = "boundary"
}

resource "aws_security_group_rule" "boundary_ssh" {
  type              = "ingress"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks       = [var.cidr_block]
  security_group_id = aws_security_group.boundary.id
  description       = "http"
}

resource "aws_security_group_rule" "websg_outbound" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.boundary.id
  description       = "outbound"
}

// Internal EC2
resource "aws_instance" "internal" {
  count = 1
  ami                    = "ami-081511b9e3af53902"
  instance_type          = "t3.micro"
  key_name               = aws_key_pair.example.key_name
  subnet_id              = aws_subnet.private_subnet.id
  vpc_security_group_ids = ["${aws_security_group.internalsg.id}"]

  tags = {
    Name = "Internal"
    application = "boundary"
  }
}

resource "aws_security_group" "internalsg" {
  name        = "dbsg"
  description = "allow 22 from web"
  vpc_id      = aws_vpc.vpc.id
}

resource "aws_security_group_rule" "internalsg" {
  type                     = "ingress"
  from_port                = 22
  to_port                  = 22
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.boundary.id
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

// Boundary AWW Key
/* 
resource "aws_iam_user" "boundary" {
  name = "boundary"
  path = "/"
}

resource "aws_iam_access_key" "boundary" {
  user = aws_iam_user.boundary.name
}

resource "aws_iam_user_policy" "BoundaryDescribeInstances" {
  name = "BoundaryDescribeInstances"
  user = aws_iam_user.boundary.name
  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "ec2:DescribeInstances"
      ],
      "Effect": "Allow",
      "Resource": "*"
    }
  ]
}
EOF
}
*/
