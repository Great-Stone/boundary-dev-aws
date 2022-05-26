// Boundary
resource "aws_instance" "boundary_worker" {
  ami                    = "ami-081511b9e3af53902"
  instance_type          = "t3.micro"
  key_name               = aws_key_pair.example.key_name
  subnet_id              = module.vpc_2.public_subnets[0].id
  vpc_security_group_ids = [module.vpc_2.security_group_id_boundary, module.vpc_2.security_group_id_ssh]

  tags = {
    Name = "boundary_worker"
  }
}

// Private EC2
resource "aws_instance" "internal" {
  count                  = var.internal_server_count
  ami                    = "ami-081511b9e3af53902"
  instance_type          = "t3.micro"
  key_name               = aws_key_pair.example.key_name
  subnet_id              = module.vpc_2.private_subnet.id
  vpc_security_group_ids = [module.vpc_2.security_group_id_ssh]

  tags = {
    Name        = "Internal"
    application = "boundary"
  }
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
    module.postgre_boundary,
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
