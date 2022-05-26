#!/bin/bash
sudo yum update -y
sudo yum install -y yum-utils
sudo yum-config-manager --add-repo https://rpm.releases.hashicorp.com/AmazonLinux/hashicorp.repo
sudo yum -y install boundary

# Boundary
sudo mkdir -p /etc/boundary.d

# config
sudo cat << EOF > /etc/boundary.d/boundary-worker.hcl
disable_mlock = true

listener "tcp" {
  address = "${worker_private_ip}:9202"
  purpose = "proxy"
  tls_disable = true
}

worker {
  name = "worker-0"
  controllers = [
    "${controller_ip}:9201"
  ]
  public_addr = "${worker_public_ip}:9202"
  tags {
    type   = ["prod", "ec2"]
    region = ["ap-northeast-2"]
  }
}

kms "aead" {
  purpose   = "worker-auth"
  aead_type = "aes-gcm"
  key       = "8fZBjCUfN0TzjEGLQldGY4+iE9AkOvCfjh7+p0GtRBQ="
  key_id    = "global_worker-auth"
}

kms "aead" {
  purpose   = "config"
  aead_type = "aes-gcm"
  key       = "7xtkEoS5EXPbgynwd+dDLHopaCqK8cq0Rpep4eooaTs="
}
EOF

# Service
sudo cat << EOF > /etc/systemd/system/boundary-worker.service
[Unit]
Description=boundary worker

[Service]
ExecStart=/usr/bin/boundary server -config /etc/boundary.d/boundary-worker.hcl
User=boundary
Group=boundary
LimitMEMLOCK=infinity
AmbientCapabilities=CAP_IPC_LOCK
CapabilityBoundingSet=CAP_SYSLOG CAP_IPC_LOCK

[Install]
WantedBy=multi-user.target
EOF

sudo adduser --system --user-group boundary || true
sudo chown boundary:boundary /etc/boundary.d/boundary-worker.hcl

sudo chmod 664 /etc/systemd/system/boundary-worker.service
sudo chown boundary:boundary /usr/bin/boundary
sudo systemctl daemon-reload
sudo systemctl enable boundary-worker
sudo systemctl start boundary-worker
sudo systemctl status boundary-worker
