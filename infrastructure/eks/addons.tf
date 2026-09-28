# Cluster add-ons installed with Helm: AWS Load Balancer Controller and the monitoring stack.

# --- AWS Load Balancer Controller (registers pod IPs into the Terraform-managed target groups) ---

data "aws_iam_policy_document" "pod_identity_assume" {
  statement {
    actions = ["sts:AssumeRole", "sts:TagSession"]
    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lb_controller" {
  name               = "${local.name}-lb-controller"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_assume.json
}

# Official policy for controller v3.5.0:
# https://github.com/kubernetes-sigs/aws-load-balancer-controller/blob/v3.5.0/docs/install/iam_policy.json
resource "aws_iam_policy" "lb_controller" {
  name   = "${local.name}-lb-controller"
  policy = file("${path.module}/policies/aws-load-balancer-controller.json")
}

resource "aws_iam_role_policy_attachment" "lb_controller" {
  role       = aws_iam_role.lb_controller.name
  policy_arn = aws_iam_policy.lb_controller.arn
}

resource "aws_eks_pod_identity_association" "lb_controller" {
  cluster_name    = aws_eks_cluster.main.name
  namespace       = "kube-system"
  service_account = "aws-load-balancer-controller"
  role_arn        = aws_iam_role.lb_controller.arn
}

resource "helm_release" "lb_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = "3.5.0"
  namespace  = "kube-system"

  values = [yamlencode({
    clusterName    = aws_eks_cluster.main.name
    region         = var.region
    vpcId          = aws_vpc.main.id
    replicaCount   = 1
    serviceAccount = { name = "aws-load-balancer-controller" }
  })]

  depends_on = [
    aws_eks_node_group.main,
    aws_eks_addon.pod_identity,
    aws_eks_pod_identity_association.lb_controller,
    aws_iam_role_policy_attachment.lb_controller,
  ]
}

# --- Monitoring: Prometheus Operator + Prometheus + Grafana + node/kube-state metrics ---

resource "helm_release" "kube_prometheus_stack" {
  name             = "kube-prometheus-stack"
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "kube-prometheus-stack"
  version          = "91.8.0"
  namespace        = "monitoring"
  create_namespace = true
  timeout          = 900

  values = [yamlencode({
    fullnameOverride = "kps"
    alertmanager     = { enabled = false }

    # EKS manages the control plane; these components can't be scraped and would show as "down".
    kubeControllerManager = { enabled = false }
    kubeScheduler         = { enabled = false }
    kubeEtcd              = { enabled = false }
    kubeProxy             = { enabled = false }

    prometheus = {
      prometheusSpec = {
        # Scrape every ServiceMonitor/PodMonitor in the cluster (e.g. k8s/backend-servicemonitor.yaml).
        serviceMonitorSelectorNilUsesHelmValues = false
        podMonitorSelectorNilUsesHelmValues     = false
        retention                               = "7d"
        resources                               = { requests = { cpu = "100m", memory = "512Mi" } }
      }
    }

    grafana = {
      fullnameOverride = "grafana"
      service          = { port = 80 }
    }
  })]

  set_sensitive = [{
    name  = "grafana.adminPassword"
    value = random_password.grafana.result
  }]

  # The LB controller registers a webhook for all Services; installing in parallel fails with
  # "no endpoints available for service aws-load-balancer-webhook-service".
  depends_on = [aws_eks_node_group.main, helm_release.lb_controller]
}

resource "helm_release" "postgres_exporter" {
  name       = "postgres-exporter"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "prometheus-postgres-exporter"
  version    = "8.2.0"
  namespace  = "monitoring"

  values = [yamlencode({
    config = {
      datasource = {
        host     = aws_db_instance.main.address
        port     = "5432"
        user     = aws_db_instance.main.username
        database = aws_db_instance.main.db_name
        sslmode  = "require"
      }
    }
    serviceMonitor = { enabled = true }
  })]

  set_sensitive = [{
    name  = "config.datasource.password"
    value = random_password.db.result
  }]

  # ServiceMonitor CRD comes from kube-prometheus-stack.
  depends_on = [helm_release.kube_prometheus_stack]
}
