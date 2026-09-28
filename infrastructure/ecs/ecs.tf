resource "aws_ecs_cluster" "main" {
  name = local.name
}

# Private DNS (backend.freshmart.local) so Prometheus can discover every backend task.
resource "aws_service_discovery_private_dns_namespace" "main" {
  name = "${local.name}.local"
  vpc  = aws_vpc.main.id
}

resource "aws_service_discovery_service" "backend" {
  name = "backend"

  dns_config {
    namespace_id   = aws_service_discovery_private_dns_namespace.main.id
    routing_policy = "MULTIVALUE"

    dns_records {
      type = "A"
      ttl  = 10
    }
  }
}

resource "aws_cloudwatch_log_group" "ecs" {
  for_each          = toset(["backend", "migrate", "prometheus", "postgres-exporter"])
  name              = "/ecs/${local.name}/${each.key}"
  retention_in_days = 14
}

# --- IAM ---

data "aws_iam_policy_document" "ecs_tasks_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

# Used by the ECS agent: pull images, write logs, read secrets.
resource "aws_iam_role" "execution" {
  name               = "${local.name}-ecs-execution"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json
}

resource "aws_iam_role_policy_attachment" "execution" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy" "execution_secrets" {
  name = "read-app-secrets"
  role = aws_iam_role.execution.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue"]
      Resource = [for s in aws_secretsmanager_secret.app : s.arn]
    }]
  })
}

# Used by the running containers. Only grants ECS Exec (`aws ecs execute-command`) for debugging.
resource "aws_iam_role" "task" {
  name               = "${local.name}-ecs-task"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json
}

resource "aws_iam_role_policy" "task_exec" {
  name = "ecs-exec"
  role = aws_iam_role.task.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "ssmmessages:CreateControlChannel",
        "ssmmessages:CreateDataChannel",
        "ssmmessages:OpenControlChannel",
        "ssmmessages:OpenDataChannel",
      ]
      Resource = "*"
    }]
  })
}

# --- Task definitions ---

locals {
  backend_image    = "${aws_ecr_repository.backend.repository_url}:${var.image_tag}"
  prometheus_image = "${aws_ecr_repository.prometheus.repository_url}:${var.image_tag}"

  backend_secrets = [
    { name = "DATABASE_URL", valueFrom = aws_secretsmanager_secret.app["database-url"].arn },
    { name = "JWT_SECRET", valueFrom = aws_secretsmanager_secret.app["jwt-secret"].arn },
    { name = "ADMIN_PASSWORD", valueFrom = aws_secretsmanager_secret.app["admin-password"].arn },
  ]
  backend_environment = [
    { name = "ADMIN_EMAIL", value = var.admin_email },
  ]

  runtime_platform = {
    operating_system_family = "LINUX"
    cpu_architecture        = var.cpu_architecture
  }
}

resource "aws_ecs_task_definition" "backend" {
  family                   = "${local.name}-backend"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.backend_cpu
  memory                   = var.backend_memory
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.task.arn

  runtime_platform {
    operating_system_family = local.runtime_platform.operating_system_family
    cpu_architecture        = local.runtime_platform.cpu_architecture
  }

  container_definitions = jsonencode([{
    name      = "backend"
    image     = local.backend_image
    essential = true
    # Migrations run once per deploy as a separate task (see "migrate" below), not on every start.
    command      = ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000", "--proxy-headers", "--forwarded-allow-ips", "*"]
    portMappings = [{ containerPort = 8000, protocol = "tcp" }]
    environment  = local.backend_environment
    secrets      = local.backend_secrets
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.ecs["backend"].name
        awslogs-region        = var.region
        awslogs-stream-prefix = "backend"
      }
    }
  }])
}

# One-off task: `alembic upgrade head` + seed. Run by infrastructure/scripts/deploy.sh before rolling the service.
resource "aws_ecs_task_definition" "migrate" {
  family                   = "${local.name}-migrate"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.task.arn

  runtime_platform {
    operating_system_family = local.runtime_platform.operating_system_family
    cpu_architecture        = local.runtime_platform.cpu_architecture
  }

  container_definitions = jsonencode([{
    name        = "migrate"
    image       = local.backend_image
    essential   = true
    command     = ["sh", "-c", "alembic upgrade head && python -m app.seed"]
    environment = local.backend_environment
    secrets     = local.backend_secrets
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.ecs["migrate"].name
        awslogs-region        = var.region
        awslogs-stream-prefix = "migrate"
      }
    }
  }])
}

resource "aws_ecs_task_definition" "prometheus" {
  family                   = "${local.name}-prometheus"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 512
  memory                   = 1024
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.task.arn

  runtime_platform {
    operating_system_family = local.runtime_platform.operating_system_family
    cpu_architecture        = local.runtime_platform.cpu_architecture
  }

  container_definitions = jsonencode([
    {
      name      = "prometheus"
      image     = local.prometheus_image
      essential = true
      command = [
        "--config.file=/etc/prometheus/prometheus.yml",
        "--storage.tsdb.path=/prometheus",
        "--storage.tsdb.retention.time=15d",
        "--web.enable-lifecycle",
      ]
      portMappings = [{ containerPort = 9090, protocol = "tcp" }]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.ecs["prometheus"].name
          awslogs-region        = var.region
          awslogs-stream-prefix = "prometheus"
        }
      }
    },
    {
      # Sidecar: Prometheus scrapes it at localhost:9187.
      name      = "postgres-exporter"
      image     = "quay.io/prometheuscommunity/postgres-exporter:latest"
      essential = false
      environment = [
        { name = "DATA_SOURCE_URI", value = "${aws_db_instance.main.address}:5432/${aws_db_instance.main.db_name}?sslmode=require" },
        { name = "DATA_SOURCE_USER", value = aws_db_instance.main.username },
      ]
      secrets = [
        { name = "DATA_SOURCE_PASS", valueFrom = aws_secretsmanager_secret.app["db-password"].arn },
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.ecs["postgres-exporter"].name
          awslogs-region        = var.region
          awslogs-stream-prefix = "postgres-exporter"
        }
      }
    },
  ])
}

# --- Services ---

resource "aws_ecs_service" "backend" {
  name                              = "${local.name}-backend"
  cluster                           = aws_ecs_cluster.main.id
  task_definition                   = aws_ecs_task_definition.backend.arn
  desired_count                     = var.backend_desired_count
  launch_type                       = "FARGATE"
  enable_execute_command            = true
  health_check_grace_period_seconds = 30

  network_configuration {
    subnets          = aws_subnet.private[*].id
    security_groups  = [aws_security_group.backend.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.backend.arn
    container_name   = "backend"
    container_port   = 8000
  }

  service_registries {
    registry_arn = aws_service_discovery_service.backend.arn
  }

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  depends_on = [aws_lb_listener_rule.api]
}

# Note: Prometheus storage is the task's ephemeral disk, so history resets when the task is replaced.
# For durable metrics, point remote_write at Amazon Managed Service for Prometheus.
resource "aws_ecs_service" "prometheus" {
  name                   = "${local.name}-prometheus"
  cluster                = aws_ecs_cluster.main.id
  task_definition        = aws_ecs_task_definition.prometheus.arn
  desired_count          = 1
  launch_type            = "FARGATE"
  enable_execute_command = true

  # Single instance: stop the old task before starting a new one.
  deployment_minimum_healthy_percent = 0
  deployment_maximum_percent         = 100

  network_configuration {
    subnets          = aws_subnet.private[*].id
    security_groups  = [aws_security_group.prometheus.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.prometheus.arn
    container_name   = "prometheus"
    container_port   = 9090
  }

  depends_on = [aws_lb_listener.prometheus]
}
