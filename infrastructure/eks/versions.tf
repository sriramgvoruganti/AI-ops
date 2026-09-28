terraform {
  required_version = ">= 1.6"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.70"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.6"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 3.0"
    }
  }

  # State is local for now. For team use, move it to S3 with locking:
  # backend "s3" { bucket = "...", key = "freshmart-eks/terraform.tfstate", region = "us-east-2", use_lockfile = true }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = var.project
      ManagedBy = "terraform"
    }
  }
}

# Installs cluster add-ons (load balancer controller, monitoring) with Helm. Authenticates with the
# same AWS credentials Terraform uses.
provider "helm" {
  kubernetes = {
    host                   = aws_eks_cluster.main.endpoint
    cluster_ca_certificate = base64decode(aws_eks_cluster.main.certificate_authority[0].data)
    exec = {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", aws_eks_cluster.main.name, "--region", var.region]
    }
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_caller_identity" "current" {}

locals {
  name = var.project
  azs  = slice(data.aws_availability_zones.available.names, 0, 2)
}
