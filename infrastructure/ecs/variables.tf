variable "region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "us-east-2"
}

variable "project" {
  description = "Name prefix for all resources. infrastructure/scripts/deploy.sh assumes \"freshmart\"."
  type        = string
  default     = "freshmart"
}

variable "image_tag" {
  description = "Tag of the backend and prometheus images in ECR (set by deploy.sh)."
  type        = string
  default     = "latest"
}

variable "cpu_architecture" {
  description = "Fargate CPU architecture. ARM64 is cheaper and matches Apple Silicon builds."
  type        = string
  default     = "ARM64"

  validation {
    condition     = contains(["ARM64", "X86_64"], var.cpu_architecture)
    error_message = "cpu_architecture must be ARM64 or X86_64."
  }
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.20.0.0/16"
}

# --- Backend ---

variable "backend_desired_count" {
  description = "Number of backend tasks. 2 spreads them across both AZs."
  type        = number
  default     = 2
}

variable "backend_cpu" {
  description = "Backend task CPU units (1024 = 1 vCPU)."
  type        = number
  default     = 256
}

variable "backend_memory" {
  description = "Backend task memory (MiB)."
  type        = number
  default     = 512
}

variable "admin_email" {
  description = "Email for the seeded store admin. Its password is generated and stored in Secrets Manager."
  type        = string
  default     = "admin@example.com"
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

# --- Monitoring ---

variable "prometheus_allowed_cidrs" {
  description = "CIDRs allowed to reach the Prometheus UI on the load balancer's port 9090 (e.g. [\"203.0.113.4/32\"]). Empty = no access."
  type        = list(string)
  default     = []
}
