# Boundary Dev mode with AWS

## Create SSH key

```bash
ssh-keygen -t rsa -b 4096 -f ./.ssh/id_rsa
```

## Terraform Apply

```bash
terraform apply --auto-approve
```

## Run

```bash
# PUBLIC_IP is aws_instance.boundary public_ip
export PUBLIC_IP="3.36.87.59"
export PRIVATE_IP="10.0.1.69"
export BOUNDARY_DEV_CONTROLLER_API_LISTEN_ADDRESS=${PRIVATE_IP}
export BOUNDARY_DEV_CONTROLLER_CLUSTER_LISTEN_ADDRESS="0.0.0.0"
export BOUNDARY_DEV_WORKER_PUBLIC_ADDRESS=${PUBLIC_IP}
export BOUNDARY_DEV_WORKER_PROXY_LISTEN_ADDRESS=${PRIVATE_IP}
export BOUNDARY_DEV_PASSWORD="password"
boundary dev
```