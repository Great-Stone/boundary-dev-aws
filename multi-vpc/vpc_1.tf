// Boundary Controller
resource "aws_instance" "boundary" {
  ami                    = "ami-081511b9e3af53902"
  instance_type          = "t3.micro"
  key_name               = aws_key_pair.example.key_name
  subnet_id              = module.vpc_1.public_subnets[0].id
  vpc_security_group_ids = [module.vpc_1.security_group_id_boundary, module.vpc_1.security_group_id_ssh]
  /* user_data              = data.template_file.controller.rendered */

  tags = {
    Name = "boundary"
  }
}

## RDS 구성
resource "aws_security_group" "rds" {
  name   = "postgresql_rds"
  vpc_id = module.vpc_1.vpc.id

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
  cidr_blocks       = ["${jsondecode(data.http.myip.body).ip}/32", module.vpc_1.vpc.cidr_block, module.vpc_2.vpc.cidr_block, "0.0.0.0/0"]
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
  subnet_ids = module.vpc_1.public_subnets[*].id
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
  length           = 16
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
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

module "postgre_boundary" {
  source = "./postgre_boundary"

  address  = aws_db_instance.boundary.address
  username = var.rds_username
  password = random_password.password.result
}

data "aws_network_interface" "rds" {
  filter {
    name   = "subnet-id"
    values = module.vpc_1.public_subnets[*].id
  }
  filter {
    name   = "description"
    values = ["RDSNetworkInterface"]

  }
  depends_on = [aws_db_instance.boundary]
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
    module.postgre_boundary
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