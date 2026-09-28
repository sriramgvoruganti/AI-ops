#!/usr/bin/env bash
# Build, push and deploy FreshMart to AWS.
#
#   infrastructure/scripts/deploy.sh               # prompts before each terraform apply
#   AUTO_APPROVE=1 infrastructure/scripts/deploy.sh
#
# Steps: ECR repos -> build & push images -> infra + migration task -> run migrations
#        -> roll ECS services -> build & upload frontend -> invalidate CloudFront.
set -euo pipefail

INFRA_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ROOT_DIR="$(cd "$INFRA_DIR/.." && pwd)"
cd "$INFRA_DIR"

PROJECT="freshmart" # must match var.project
REGION="${AWS_REGION:-$(terraform output -raw region 2>/dev/null || true)}"
REGION="${REGION:-us-east-2}"
TAG="${IMAGE_TAG:-$(git -C "$ROOT_DIR" rev-parse --short HEAD)-$(date +%Y%m%d%H%M%S)}"
PLATFORM="${PLATFORM:-linux/arm64}" # must match var.cpu_architecture
APPROVE=()
[[ -n "${AUTO_APPROVE:-}" ]] && APPROVE=(-auto-approve)
TF_VARS=(-var "region=$REGION" -var "image_tag=$TAG")

export AWS_REGION="$REGION" AWS_PAGER=""
step() { printf '\n\033[1;32m==> %s\033[0m\n' "$*"; }

step "Deploying image tag $TAG to $REGION"
aws sts get-caller-identity --query Arn --output text

step "1/6 Ensure ECR repositories exist"
terraform init -input=false >/dev/null
terraform apply -input=false "${APPROVE[@]}" "${TF_VARS[@]}" \
  -target=aws_ecr_repository.backend -target=aws_ecr_repository.prometheus

BACKEND_REPO=$(aws ecr describe-repositories --repository-names "$PROJECT-backend" --query 'repositories[0].repositoryUri' --output text)
PROM_REPO=$(aws ecr describe-repositories --repository-names "$PROJECT-prometheus" --query 'repositories[0].repositoryUri' --output text)

step "2/6 Build and push images ($PLATFORM)"
aws ecr get-login-password | docker login --username AWS --password-stdin "${BACKEND_REPO%%/*}"
docker build --platform "$PLATFORM" -t "$BACKEND_REPO:$TAG" "$ROOT_DIR/backend"
docker push "$BACKEND_REPO:$TAG"
docker build --platform "$PLATFORM" -t "$PROM_REPO:$TAG" "$ROOT_DIR/monitoring"
docker push "$PROM_REPO:$TAG"

step "3/6 Provision network, database, secrets and migration task"
terraform apply -input=false "${APPROVE[@]}" "${TF_VARS[@]}" \
  -target=aws_ecs_cluster.main -target=aws_ecs_task_definition.migrate

step "4/6 Run database migrations"
SUBNETS=$(aws ec2 describe-subnets --filters "Name=tag:Name,Values=$PROJECT-private-*" \
  --query 'Subnets[].SubnetId' --output text | tr '\t' ',')
SG=$(aws ec2 describe-security-groups --filters "Name=group-name,Values=$PROJECT-backend" \
  --query 'SecurityGroups[0].GroupId' --output text)
TASK_ARN=$(aws ecs run-task --cluster "$PROJECT" --task-definition "$PROJECT-migrate" --launch-type FARGATE \
  --network-configuration "awsvpcConfiguration={subnets=[$SUBNETS],securityGroups=[$SG],assignPublicIp=DISABLED}" \
  --query 'tasks[0].taskArn' --output text)
echo "Migration task: $TASK_ARN"
aws ecs wait tasks-stopped --cluster "$PROJECT" --tasks "$TASK_ARN"
EXIT_CODE=$(aws ecs describe-tasks --cluster "$PROJECT" --tasks "$TASK_ARN" --query 'tasks[0].containers[0].exitCode' --output text)
if [[ "$EXIT_CODE" != "0" ]]; then
  echo "Migration failed (exit code $EXIT_CODE). Logs:" >&2
  aws logs tail "/ecs/$PROJECT/migrate" --since 15m >&2 || true
  exit 1
fi
aws logs tail "/ecs/$PROJECT/migrate" --since 15m || true

step "5/6 Apply everything else and roll ECS services"
terraform apply -input=false "${APPROVE[@]}" "${TF_VARS[@]}"
echo "Waiting for services to become stable..."
aws ecs wait services-stable --cluster "$PROJECT" --services "$PROJECT-backend" "$PROJECT-prometheus"

step "6/6 Build and publish frontend"
BUCKET=$(terraform output -raw frontend_bucket)
DIST_ID=$(terraform output -raw cloudfront_distribution_id)
(cd "$ROOT_DIR/frontend" && npm ci --silent && npm run build)
# Hashed assets are immutable; index.html must always be revalidated so new deploys show up.
aws s3 sync "$ROOT_DIR/frontend/dist" "s3://$BUCKET" --delete --exclude index.html \
  --cache-control "public,max-age=31536000,immutable"
aws s3 cp "$ROOT_DIR/frontend/dist/index.html" "s3://$BUCKET/index.html" --cache-control "no-cache"
aws cloudfront create-invalidation --distribution-id "$DIST_ID" --paths "/*" --query 'Invalidation.Id' --output text

step "Done"
echo "Storefront:  $(terraform output -raw app_url)"
echo "Prometheus:  $(terraform output -raw prometheus_url)  (from prometheus_allowed_cidrs only)"
echo "Admin login: $(terraform output -raw admin_email) / run: terraform -chdir=infrastructure output -raw admin_password"
