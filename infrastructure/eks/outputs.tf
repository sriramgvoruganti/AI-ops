output "app_url" {
  description = "Storefront URL."
  value       = "https://${aws_cloudfront_distribution.main.domain_name}"
}

output "prometheus_url" {
  description = "Prometheus UI (only reachable from monitoring_allowed_cidrs)."
  value       = "http://${aws_lb.main.dns_name}:9090"
}

output "grafana_url" {
  description = "Grafana (only reachable from monitoring_allowed_cidrs). User: admin."
  value       = "http://${aws_lb.main.dns_name}:3000"
}

output "grafana_admin_password" {
  value     = random_password.grafana.result
  sensitive = true
}

output "admin_email" {
  value = var.admin_email
}

output "admin_password" {
  description = "Seeded store admin password. Show with: terraform output -raw admin_password"
  value       = random_password.admin.result
  sensitive   = true
}

output "region" {
  value = var.region
}

output "cluster_name" {
  value = aws_eks_cluster.main.name
}

output "configure_kubectl" {
  value = "aws eks update-kubeconfig --region ${var.region} --name ${aws_eks_cluster.main.name}"
}

output "backend_repository_url" {
  value = aws_ecr_repository.backend.repository_url
}

output "backend_target_group_arn" {
  value = aws_lb_target_group.backend.arn
}

output "prometheus_target_group_arn" {
  value = aws_lb_target_group.prometheus.arn
}

output "grafana_target_group_arn" {
  value = aws_lb_target_group.grafana.arn
}

output "frontend_bucket" {
  value = aws_s3_bucket.frontend.bucket
}

output "cloudfront_distribution_id" {
  value = aws_cloudfront_distribution.main.id
}

output "rds_endpoint" {
  value = aws_db_instance.main.address
}

output "github_deploy_role_arn" {
  description = "Set as the AWS_DEPLOY_ROLE_ARN repository variable in GitHub."
  value       = aws_iam_role.github_deploy.arn
}
