# EKS control plane + a managed node group in the private subnets.

data "aws_iam_policy_document" "eks_assume" {
  statement {
    actions = ["sts:AssumeRole", "sts:TagSession"]
    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "cluster" {
  name               = "${local.name}-cluster"
  assume_role_policy = data.aws_iam_policy_document.eks_assume.json
}

resource "aws_iam_role_policy_attachment" "cluster" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_eks_cluster" "main" {
  name     = local.name
  version  = var.kubernetes_version
  role_arn = aws_iam_role.cluster.arn

  # Access is granted through EKS access entries. The identity running Terraform becomes cluster admin.
  access_config {
    authentication_mode                         = "API"
    bootstrap_cluster_creator_admin_permissions = true
  }

  vpc_config {
    subnet_ids              = concat(aws_subnet.private[*].id, aws_subnet.public[*].id)
    endpoint_private_access = true
    endpoint_public_access  = true
    public_access_cidrs     = var.cluster_endpoint_allowed_cidrs
  }

  # Auto-upgrade at end of standard support instead of silently moving to paid extended support.
  upgrade_policy {
    support_type = "STANDARD"
  }

  depends_on = [aws_iam_role_policy_attachment.cluster]
}

# --- Worker nodes ---

data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "node" {
  name               = "${local.name}-node"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

resource "aws_iam_role_policy_attachment" "node" {
  for_each = toset([
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
  ])
  role       = aws_iam_role.node.name
  policy_arn = each.value
}

resource "aws_eks_node_group" "main" {
  cluster_name = aws_eks_cluster.main.name
  # Generated name + create_before_destroy: changing instance types brings up the new group
  # before the old one is removed, so pods always have somewhere to run.
  node_group_name_prefix = "${local.name}-"
  node_role_arn          = aws_iam_role.node.arn
  subnet_ids             = aws_subnet.private[*].id

  ami_type       = var.cpu_architecture == "ARM64" ? "AL2023_ARM_64_STANDARD" : "AL2023_x86_64_STANDARD"
  capacity_type  = var.node_capacity_type
  instance_types = var.node_instance_types
  disk_size      = 20

  scaling_config {
    desired_size = var.node_count
    min_size     = 1
    max_size     = var.node_count + 2
  }

  update_config {
    max_unavailable = 1
  }

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [aws_iam_role_policy_attachment.node]
}

# Lets pods assume IAM roles (used by the AWS Load Balancer Controller).
resource "aws_eks_addon" "pod_identity" {
  cluster_name = aws_eks_cluster.main.name
  addon_name   = "eks-pod-identity-agent"

  depends_on = [aws_eks_node_group.main]
}

# --- Network access into pods (they use the EKS-managed cluster security group) ---

locals {
  cluster_sg_id = aws_eks_cluster.main.vpc_config[0].cluster_security_group_id
  alb_to_pod_ports = {
    backend    = 8000
    prometheus = 9090
    grafana    = 3000
  }
}

resource "aws_vpc_security_group_ingress_rule" "pods_from_alb" {
  for_each = local.alb_to_pod_ports

  security_group_id            = local.cluster_sg_id
  description                  = "ALB to ${each.key} pods"
  ip_protocol                  = "tcp"
  from_port                    = each.value
  to_port                      = each.value
  referenced_security_group_id = aws_security_group.alb.id
}

resource "aws_vpc_security_group_ingress_rule" "db_from_pods" {
  security_group_id            = aws_security_group.db.id
  description                  = "Postgres from EKS pods (backend, migrations, postgres-exporter)"
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  referenced_security_group_id = local.cluster_sg_id
}
