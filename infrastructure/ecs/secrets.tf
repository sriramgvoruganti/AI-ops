# Generated credentials, injected into containers from Secrets Manager at task start.
# Note: generated values are also stored in the Terraform state file, so keep state private.

resource "random_password" "db" {
  length  = 32
  special = false # keeps the DATABASE_URL free of characters that need URL-escaping
}

resource "random_password" "jwt" {
  length  = 64
  special = false
}

resource "random_password" "admin" {
  length  = 20
  special = false
}

locals {
  secrets = {
    "database-url"   = "postgresql+psycopg://${aws_db_instance.main.username}:${random_password.db.result}@${aws_db_instance.main.address}:5432/${aws_db_instance.main.db_name}"
    "db-password"    = random_password.db.result
    "jwt-secret"     = random_password.jwt.result
    "admin-password" = random_password.admin.result
  }
}

resource "aws_secretsmanager_secret" "app" {
  for_each = local.secrets

  name                    = "${local.name}/${each.key}"
  recovery_window_in_days = 0 # allow destroy + recreate without name clashes
}

resource "aws_secretsmanager_secret_version" "app" {
  for_each = local.secrets

  secret_id     = aws_secretsmanager_secret.app[each.key].id
  secret_string = each.value
}
