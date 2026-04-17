# outputs.tf — NetPulse

output "master_public_ip" {
  description = "IP publique du master"
  value       = aws_eip.master.public_ip
}

output "worker_public_ip" {
  description = "IP publique du worker"
  value       = aws_instance.k8s_worker.public_ip
}

output "ssh_master" {
  value = "ssh -i ~/.ssh/devops-aws-key ubuntu@${aws_eip.master.public_ip}"
}

output "ssh_worker" {
  value = "ssh -i ~/.ssh/devops-aws-key ubuntu@${aws_instance.k8s_worker.public_ip}"
}

output "netpulse_dashboard" {
  value = "http://${aws_eip.master.public_ip}:30000"
}

output "grafana_url" {
  value = "http://${aws_eip.master.public_ip}:31000  (admin / netpulse2025)"
}

output "prometheus_url" {
  value = "http://${aws_eip.master.public_ip}:31001"
}

output "hubble_ui_cmd" {
  value = "kubectl port-forward -n kube-system svc/hubble-ui 12000:80 --address 0.0.0.0"
}

output "vpc_id" {
  value = aws_vpc.main.id
}
