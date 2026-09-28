variable "region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "us-east-2"
}

variable "project" {
  description = "Name prefix for all resources. scripts/deploy.sh assumes \"freshmart-eks\"."
  type        = string
  default     = "freshmart-eks"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.30.0.0/16"
}

variable "admin_email" {
  description = "Email for the seeded store admin. Its password is generated and stored in Secrets Manager."
  type        = string
  default     = "admin@example.com"
}

# --- Kubernetes ---

variable "kubernetes_version" {
  description = "EKS Kubernetes version. Keep it in standard support; extended support costs 6x more."
  type        = string
  default     = "1.36"
}

variable "cluster_endpoint_allowed_cidrs" {
  description = "CIDRs allowed to reach the Kubernetes API (kubectl). Narrow this to your IP for extra safety."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "cpu_architecture" {
  description = "Worker node architecture. ARM64 (Graviton) is cheaper and matches Apple Silicon builds."
  type        = string
  default     = "ARM64"

  validation {
    condition     = contains(["ARM64", "X86_64"], var.cpu_architecture)
    error_message = "cpu_architecture must be ARM64 or X86_64."
  }
}

variable "node_instance_types" {
  description = "Worker node instance types (must match cpu_architecture). Several types improve Spot availability."
  type        = list(string)
  default     = ["t4g.medium", "t4g.large"]
}

variable "node_capacity_type" {
  description = "SPOT (~60% cheaper, can be interrupted) or ON_DEMAND."
  type        = string
  default     = "SPOT"

  validation {
    condition     = contains(["SPOT", "ON_DEMAND"], var.node_capacity_type)
    error_message = "node_capacity_type must be SPOT or ON_DEMAND."
  }
}

variable "node_count" {
  description = "Number of worker nodes."
  type        = number
  default     = 2
}

# --- Database ---

variable "db_instance_class" {
  description = "RDS instance class."
  type        = string
  default     = "db.t4g.micro"
}

variable "db_allocated_storage" {
  description = "RDS storage in GiB."
  type        = number
  default     = 20
}

variable "db_max_allocated_storage" {
  description = "Storage autoscaling ceiling in GiB. Set to 0 to disable autoscaling (a precaution on the AWS free plan)."
  type        = number
  default     = 100
}

variable "db_backup_retention_days" {
  description = "Days of automated backups to keep. The AWS free plan allows at most 1."
  type        = number
  default     = 7
}

variable "db_multi_az" {
  description = "Run RDS with a standby in a second AZ (roughly doubles DB cost)."
  type        = bool
  default     = false
}

variable "db_deletion_protection" {
  description = "Block `terraform destroy` from deleting the database. Also takes a final snapshot on delete."
  type        = bool
  default     = false
}

# --- Monitoring & cost ---

variable "monitoring_allowed_cidrs" {
  description = "CIDRs allowed to reach Prometheus (:9090) and Grafana (:3000) on the load balancer. Empty = no access."
  type        = list(string)
  default     = []
}

variable "budget_alert_email" {
  description = "Email for AWS Budgets alerts. Empty = no budget is created."
  type        = string
  default     = ""
}

variable "monthly_budget_usd" {
  description = "Monthly budget; alerts fire at 50%, 80% and 100% of it (actual) and 100% (forecast)."
  type        = number
  default     = 200
}
