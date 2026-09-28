#!/usr/bin/env bash
# Build, push and deploy FreshMart to EKS.
#
#   infrastructure/eks/scripts/deploy.sh               # prompts before each terraform apply
#   AUTO_APPROVE=1 infrastructure/eks/scripts/deploy.sh
#
# Steps: ECR repo -> build & push backend image -> terraform (VPC, EKS, RDS, ALB, CloudFront, Helm add-ons)
#        -> kubeconfig + app secret -> migration Job -> backend Deployment + monitoring bindings
#        -> build & upload frontend -> invalidate CloudFront.
set -euo pipefail

TF_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ROOT_DIR="$(cd "$TF_DIR/../.." && pwd)"
K8S_DIR="$ROOT_DIR/k8s"
cd "$TF_DIR"

PROJECT="freshmart-eks" # must match var.project
REGION="${AWS_REGION:-$(terraform output -raw region 2>/dev/null || true)}"
REGION="${REGION:-us-east-2}"
TAG="${IMAGE_TAG:-$(git -C "$ROOT_DIR" rev-parse --short HEAD)-$(date +%Y%m%d%H%M%S)}"
ARCH=$(echo 'var.cpu_architecture' | terraform console 2>/dev/null | tr -d '"')
case "$ARCH" in X86_64) DEFAULT_PLATFORM=linux/amd64 ;; *) DEFAULT_PLATFORM=linux/arm64 ;; esac
PLATFORM="${PLATFORM:-$DEFAULT_PLATFORM}"
APPROVE=()
[[ -n "${AUTO_APPROVE:-}" ]] && APPROVE=(-auto-approve)
TF_VARS=(-var "region=$REGION")

export AWS_REGION="$REGION" AWS_PAGER=""
step() { printf '\n\033[1;32m==> %s\033[0m\n' "$*"; }

# Substitute ${VAR} placeholders in a manifest and apply it.
apply_manifest() {
  sed -e "s|\${BACKEND_IMAGE}|$BACKEND_IMAGE|g" \
      -e "s|\${BACKEND_TG_ARN}|$(terraform output -raw backend_target_group_arn)|g" \
      -e "s|\${PROMETHEUS_TG_ARN}|$(terraform output -raw prometheus_target_group_arn)|g" \
      -e "s|\${GRAFANA_TG_ARN}|$(terraform output -raw grafana_target_group_arn)|g" \
      "$1" | kubectl apply -f -
}

step "Deploying image tag $TAG to $REGION"
aws sts get-caller-identity --query Arn --output text

step "1/7 Ensure ECR repository exists"
terraform init -input=false >/dev/null
terraform apply -input=false "${APPROVE[@]}" "${TF_VARS[@]}" -target=aws_ecr_repository.backend
BACKEND_REPO=$(aws ecr describe-repositories --repository-names "$PROJECT-backend" --query 'repositories[0].repositoryUri' --output text)
BACKEND_IMAGE="$BACKEND_REPO:$TAG"

step "2/7 Build and push backend image ($PLATFORM)"
aws ecr get-login-password | docker login --username AWS --password-stdin "${BACKEND_REPO%%/*}"
docker build --platform "$PLATFORM" -t "$BACKEND_IMAGE" "$ROOT_DIR/backend"
docker push "$BACKEND_IMAGE"

step "3/7 Provision AWS infrastructure and cluster add-ons (first run: ~20-25 min)"
terraform apply -input=false "${APPROVE[@]}" "${TF_VARS[@]}"

step "4/7 Configure kubectl and application secret"
CLUSTER=$(terraform output -raw cluster_name)
aws eks update-kubeconfig --name "$CLUSTER" --alias "$CLUSTER" >/dev/null
kubectl apply -f "$K8S_DIR/namespace.yaml"
secret() { aws secretsmanager get-secret-value --secret-id "$PROJECT/$1" --query SecretString --output text; }
ENV_FILE=$(mktemp) && chmod 600 "$ENV_FILE" && trap 'rm -f "$ENV_FILE"' EXIT
{
  echo "DATABASE_URL=$(secret database-url)"
  echo "JWT_SECRET=$(secret jwt-secret)"
  echo "ADMIN_PASSWORD=$(secret admin-password)"
  echo "ADMIN_EMAIL=$(terraform output -raw admin_email)"
} >"$ENV_FILE"
kubectl -n freshmart create secret generic freshmart-secrets --from-env-file="$ENV_FILE" \
  --dry-run=client -o yaml | kubectl apply -f -
rm -f "$ENV_FILE"

step "5/7 Run database migrations"
kubectl -n freshmart delete job migrate --ignore-not-found
apply_manifest "$K8S_DIR/migrate-job.yaml"
for _ in $(seq 1 120); do
  STATUS=$(kubectl -n freshmart get job migrate -o jsonpath='{.status.succeeded}/{.status.failed}')
  [[ "$STATUS" == 1/* ]] && break
  if [[ "${STATUS#*/}" =~ ^[0-9]+$ && "${STATUS#*/}" -gt 2 ]]; then
    echo "Migration failed:" >&2
    kubectl -n freshmart logs job/migrate --tail=50 >&2 || true
    exit 1
  fi
  sleep 5
done
[[ "$STATUS" == 1/* ]] || { echo "Migration timed out" >&2; kubectl -n freshmart logs job/migrate --tail=50 >&2; exit 1; }
kubectl -n freshmart logs job/migrate --tail=20

step "6/7 Roll out backend and wire load balancer + monitoring"
apply_manifest "$K8S_DIR/backend.yaml"
kubectl apply -f "$K8S_DIR/backend-servicemonitor.yaml"
apply_manifest "$K8S_DIR/target-group-bindings.yaml"
kubectl -n freshmart rollout status deployment/backend --timeout=5m

step "7/7 Build and publish frontend"
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
echo "Prometheus:  $(terraform output -raw prometheus_url)"
echo "Grafana:     $(terraform output -raw grafana_url)   (user: admin, password: terraform -chdir=infrastructure/eks output -raw grafana_admin_password)"
echo "Store admin: $(terraform output -raw admin_email)   (password: terraform -chdir=infrastructure/eks output -raw admin_password)"
echo "kubectl:     kubectl config use-context $CLUSTER"
