output "app_url" {
  description = "Storefront URL."
  value       = "https://${aws_cloudfront_distribution.main.domain_name}"
}

output "prometheus_url" {
  description = "Prometheus UI (only reachable from prometheus_allowed_cidrs)."
  value       = "http://${aws_lb.main.dns_name}:9090"
}

output "admin_email" {
  value = var.admin_email
}

output "admin_password" {
  description = "Seeded admin password. Show with: terraform output -raw admin_password"
  value       = random_password.admin.result
  sensitive   = true
}

output "backend_repository_url" {
  value = aws_ecr_repository.backend.repository_url
}

output "prometheus_repository_url" {
  value = aws_ecr_repository.prometheus.repository_url
}

output "frontend_bucket" {
  value = aws_s3_bucket.frontend.bucket
}

output "cloudfront_distribution_id" {
  value = aws_cloudfront_distribution.main.id
}

output "ecs_cluster" {
  value = aws_ecs_cluster.main.name
}

output "rds_endpoint" {
  value = aws_db_instance.main.address
}

output "region" {
  value = var.region
}
