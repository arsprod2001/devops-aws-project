# main.tf — NetPulse Infrastructure AWS
# Crée 2 EC2 (master + worker) pour le cluster K8s avec Cilium

terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# ─── Master K8s ───────────────────────────────────────────────────
resource "aws_instance" "k8s_master" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  key_name               = var.key_pair_name
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.k8s_master.id]

  root_block_device {
    volume_type           = "gp2"
    volume_size           = 20
    delete_on_termination = true
  }

  user_data = <<-EOF
    #!/bin/bash
    apt-get update -y
    apt-get install -y curl wget git vim htop unzip

    # Désactiver le swap (requis pour K8s ET Cilium eBPF)
    swapoff -a
    sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

    # Modules kernel requis pour Cilium eBPF
    modprobe overlay
    modprobe br_netfilter

    # Configuration réseau
    cat <<EOT > /etc/sysctl.d/k8s.conf
    net.bridge.bridge-nf-call-iptables  = 1
    net.bridge.bridge-nf-call-ip6tables = 1
    net.ipv4.ip_forward                 = 1
    EOT
    sysctl --system

    echo "✅ Master préparé pour Cilium + K8s"
  EOF

  tags = {
    Name        = "${var.project_name}-k8s-master"
    Role        = "master"
    Environment = var.environment
  }
}

# ─── Worker K8s ───────────────────────────────────────────────────
resource "aws_instance" "k8s_worker" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  key_name               = var.key_pair_name
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.k8s_worker.id]

  root_block_device {
    volume_type           = "gp2"
    volume_size           = 20
    delete_on_termination = true
  }

  user_data = <<-EOF
    #!/bin/bash
    apt-get update -y
    apt-get install -y curl wget git vim htop

    swapoff -a
    sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

    modprobe overlay
    modprobe br_netfilter

    cat <<EOT > /etc/sysctl.d/k8s.conf
    net.bridge.bridge-nf-call-iptables  = 1
    net.bridge.bridge-nf-call-ip6tables = 1
    net.ipv4.ip_forward                 = 1
    EOT
    sysctl --system
  EOF

  tags = {
    Name        = "${var.project_name}-k8s-worker"
    Role        = "worker"
    Environment = var.environment
  }
}

# ─── Elastic IP (IP fixe pour le master) ──────────────────────────
resource "aws_eip" "master" {
  instance = aws_instance.k8s_master.id
  domain   = "vpc"

  tags = {
    Name = "${var.project_name}-master-eip"
  }
}
