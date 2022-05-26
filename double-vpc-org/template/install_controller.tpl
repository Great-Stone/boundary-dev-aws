#!/bin/bash
sudo yum update -y
sudo yum install -y yum-utils
sudo yum-config-manager --add-repo https://rpm.releases.hashicorp.com/AmazonLinux/hashicorp.repo
sudo yum -y install boundary

# Boundary
sudo mkdir -p /etc/boundary.d

# config
sudo cat << EOF > /etc/boundary.d/boundary-controller.hcl
disable_mlock = true

controller {
  name = "controller-0"
  database {
    url = "postgresql://${postgresql_username}:${postgresql_password}@${postgresql_ip}:${postgresql_port}/boundary"
  }
  public_cluster_addr = "${controller_public_ip}:9201"
}

listener "tcp" {
  address = "${controller_private_ip}:9200"
  purpose = "api"
  tls_disable = true
}

listener "tcp" {
  address = "${controller_private_ip}:9201"
  purpose = "cluster"
  tls_disable = true
}

kms "aead" {
  purpose = "root"
  aead_type = "aes-gcm"
  key = "sP1fnF5Xz85RrXyELHFeZg9Ad2qt4Z4bgNHVGtD6ung="
  key_id = "global_root"
}

kms "aead" {
  purpose = "worker-auth"
  aead_type = "aes-gcm"
  key = "8fZBjCUfN0TzjEGLQldGY4+iE9AkOvCfjh7+p0GtRBQ="
  key_id = "global_worker-auth"
}

kms "aead" {
    purpose   = "recovery"
    aead_type = "aes-gcm"
    key       = "8fZBjCUfN0TzjEGLQldGY4+iE9AkOvCfjh7+p0GtRBQ="
    key_id    = "global_recovery"
}
EOF

# Service
sudo cat << EOF > /etc/systemd/system/boundary-controller.service
[Unit]
Description=boundary controller

[Service]
ExecStart=/usr/bin/boundary server -config /etc/boundary.d/boundary-controller.hcl
User=boundary
Group=boundary
LimitMEMLOCK=infinity
AmbientCapabilities=CAP_IPC_LOCK
CapabilityBoundingSet=CAP_SYSLOG CAP_IPC_LOCK

[Install]
WantedBy=multi-user.target
EOF

sudo adduser --system --user-group boundary || true
sudo chown boundary:boundary /etc/boundary.d/boundary-controller.hcl

sudo boundary database init \
   -skip-auth-method-creation \
   -skip-host-resources-creation \
   -skip-scopes-creation \
   -skip-target-creation \
   -config /etc/boundary.d/boundary-controller.hcl || true

sudo chmod 664 /etc/systemd/system/boundary-controller.service
sudo chown boundary:boundary /usr/bin/boundary
sudo systemctl daemon-reload
sudo systemctl enable boundary-controller
sudo systemctl start boundary-controller
sudo systemctl status boundary-controller
