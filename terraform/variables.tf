# variables.tf — NetPulse

variable "aws_region" {
  description = "Région AWS"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Nom du projet"
  type        = string
  default     = "netpulse"
}

variable "environment" {
  description = "Environnement"
  type        = string
  default     = "dev"
}

variable "vpc_cidr" {
  description = "CIDR du VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  type    = string
  default = "10.0.1.0/24"
}

variable "private_subnet_cidr" {
  type    = string
  default = "10.0.2.0/24"
}

variable "instance_type" {
  description = "Type d'instance EC2 — t2.medium recommandé pour Cilium + Prometheus"
  type        = string
  default     = "t2.medium"
  # IMPORTANT : t2.micro est insuffisant pour Cilium + kube-prometheus-stack
  # t2.medium (2 vCPU, 4 Go RAM) est le minimum raisonnable
  # t2.small peut fonctionner mais avec des risques d'OOM
}

variable "key_pair_name" {
  type    = string
  default = "devops-aws-key"
}

variable "ami_id" {
  description = "Ubuntu 22.04 LTS — us-east-1"
  type        = string
  default     = "ami-0fc5d935ebf8bc3bc"
}

variable "docker_username" {
  type    = string
  default = "arsprod01"
}
