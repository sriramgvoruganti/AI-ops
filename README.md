# FreshMart — grocery chain storefront

| Layer    | Stack                                              |
| -------- | -------------------------------------------------- |
| Frontend | React 19 + TypeScript + Vite, React Router         |
| Backend  | FastAPI, SQLAlchemy 2, Alembic, JWT auth (bcrypt)  |
| Database | PostgreSQL 16                                      |
| Metrics  | Prometheus, postgres-exporter (+ Grafana on EKS)   |
| Cloud    | AWS via Terraform: EKS or ECS, RDS, CloudFront     |

**Features:** product catalog with search and category filters, cart and checkout (with stock
checks and row locking to prevent overselling), order history with cancellation, customer/admin
accounts, and an admin panel for products, categories, inventory and order status.

## Run with Docker (recommended)

```bash
docker compose up --build
```

- Shop: http://localhost:5173
- API docs (Swagger): http://localhost:8000/api/docs
- Admin login: `admin@example.com` / `admin12345` (override with `ADMIN_EMAIL` / `ADMIN_PASSWORD`)
- Prometheus: http://localhost:9090

On startup the backend runs migrations and seeds a starter catalog (idempotent).
Code changes hot-reload in both containers. Reset the database with `docker compose down -v`.

## Run without Docker

Requires Python 3.11+, Node 20+ and a local Postgres (or just the DB container: `docker compose up db`).

```bash
# Backend
cd backend
python3 -m venv .venv && .venv/bin/pip install -r requirements-dev.txt
.venv/bin/alembic upgrade head && .venv/bin/python -m app.seed
.venv/bin/uvicorn app.main:app --reload            # http://localhost:8000

# Frontend (new terminal)
cd frontend
npm install && npm run dev                          # http://localhost:5173, proxies /api -> :8000
```

## Monitoring

Prometheus (config in `monitoring/prometheus.yml`) scrapes every 15s:

| Job        | Target                    | What                                            |
| ---------- | ------------------------- | ----------------------------------------------- |
| `backend`  | `backend:8000/metrics`    | HTTP request rate/latency + store metrics below |
| `postgres` | `postgres-exporter:9187`  | Connections, transactions, table/DB stats       |

Store metrics (defined in `backend/app/metrics.py`):

| Metric                                   | Type    | Labels         |
| ---------------------------------------- | ------- | -------------- |
| `freshmart_orders_placed_total`          | counter |                |
| `freshmart_order_revenue_dollars_total`  | counter |                |
| `freshmart_order_items_total`            | counter |                |
| `freshmart_orders_cancelled_total`       | counter | `cancelled_by` |
| `freshmart_checkout_failures_total`      | counter | `reason`       |

Example queries:

```promql
sum(rate(http_requests_total[5m])) by (handler)                  # request rate per endpoint
histogram_quantile(0.95, sum(rate(http_request_duration_seconds_bucket[5m])) by (le))  # p95 latency
increase(freshmart_order_revenue_dollars_total[1h])              # revenue in the last hour
sum(rate(freshmart_checkout_failures_total[15m])) by (reason)    # why checkouts fail
```

`/metrics` lives outside `/api`, so the frontend proxy doesn't expose it. After editing
`prometheus.yml`, reload without restarting: `curl -X POST localhost:9090/-/reload`.

Counters live in process memory and reset when the backend restarts (`rate()`/`increase()`
handle that). If you run uvicorn with multiple workers, enable prometheus_client's
[multiprocess mode](https://prometheus.github.io/client_python/multiprocess/).

## Tests

```bash
cd backend && .venv/bin/pytest     # uses SQLite by default; set DATABASE_URL to test against Postgres
```

## Project layout

```
backend/
  app/
    main.py          FastAPI app, router registration
    models.py        SQLAlchemy models (users, categories, products, cart_items, orders, order_items)
    schemas.py       Pydantic request/response models
    inventory.py     Stock locking and restocking
    routers/         auth, catalog, cart, orders, admin
    seed.py          Admin user + starter catalog
  alembic/           Database migrations
  tests/
monitoring/
  prometheus.yml     Scrape config (local docker compose)
  prometheus.aws.yml Scrape config for AWS, baked into monitoring/Dockerfile
infrastructure/
  eks/               Terraform for EKS + Helm add-ons, scripts/deploy.sh
  ecs/               Terraform for ECS Fargate, scripts/deploy.sh
k8s/                 Kubernetes manifests used by the EKS deploy
frontend/
  src/
    api.ts           fetch wrapper, token storage, money formatting
    auth.tsx cart.tsx  React contexts
    pages/           Shop, Cart, Orders, Login/Register, admin/*
docker-compose.yml
```

## Schema changes

Edit `backend/app/models.py`, then generate and apply a migration:

```bash
cd backend
.venv/bin/alembic revision --autogenerate -m "describe change"
.venv/bin/alembic upgrade head
```

## Deploy to AWS (Terraform)

Two alternative stacks, each a self-contained Terraform root in `infrastructure/`:

| | `infrastructure/eks/` (Kubernetes) | `infrastructure/ecs/` (simpler, cheaper) |
|---|---|---|
| Compute | EKS 1.36 + managed node group (2× Graviton, Spot by default) | ECS Fargate |
| App manifests | `k8s/` (Deployment, migration Job, ServiceMonitor, TargetGroupBindings) | ECS task definitions in Terraform |
| Monitoring | kube-prometheus-stack (Prometheus + Grafana) + postgres-exporter via Helm | Prometheus task + exporter sidecar |
| Rough cost (idle, us-east-2) | ~$175–205/month (EKS control plane alone is $73) | ~$90–110/month |

Both share the same shape: VPC across 2 AZs (ALB + NAT in public subnets, compute + RDS in private),
RDS Postgres 16, ECR, generated secrets in Secrets Manager, and CloudFront serving the React build from
S3 with `/api/*` routed to the ALB (so the site is HTTPS on `*.cloudfront.net` without a custom domain).

### EKS

```
CloudFront (HTTPS) ─┬─ /*      → S3 (React build)
                    └─ /api/*  → ALB:80 ──→ backend pods ×2 ──→ RDS Postgres 16
ALB :9090 / :3000 (your IP only) → Prometheus / Grafana pods (namespace: monitoring)
```

The ALB is created by Terraform (so CloudFront can reference it); the AWS Load Balancer Controller
registers pod IPs into its target groups through `TargetGroupBinding` objects.

**Prerequisites:** Terraform ≥ 1.6, AWS CLI v2 with credentials, `kubectl`, Docker running, Node 20+.

```bash
cp infrastructure/eks/terraform.tfvars.example infrastructure/eks/terraform.tfvars   # your IP, budget email
infrastructure/eks/scripts/deploy.sh                                                 # prompts before each apply
```

The script builds and pushes the backend image, applies Terraform (first run ~20–25 min), creates the
`freshmart-secrets` Kubernetes Secret from Secrets Manager, runs the `migrate` Job, rolls out the backend,
then publishes the frontend. Re-run it for every release.

```bash
kubectl config use-context freshmart-eks
kubectl -n freshmart get pods
terraform -chdir=infrastructure/eks output -raw admin_password          # store admin
terraform -chdir=infrastructure/eks output -raw grafana_admin_password  # Grafana user "admin"
terraform -chdir=infrastructure/eks destroy                             # tear everything down
```

### ECS

```bash
cp infrastructure/ecs/terraform.tfvars.example infrastructure/ecs/terraform.tfvars
infrastructure/ecs/scripts/deploy.sh
```

Uses `monitoring/Dockerfile` + `monitoring/prometheus.aws.yml` for its Prometheus image.

### Known limits (both)

Terraform state is local (`infrastructure/*/terraform.tfstate`, contains generated secrets — never commit
it; use an S3 backend for team use). Prometheus data is ephemeral. No custom domain (add Route 53 + ACM).

## Before production

- Set a strong `JWT_SECRET` and change the admin password.
- Add a payment provider (checkout currently records orders as pay-on-delivery).
- Serve the frontend as a static build (`npm run build`) behind a reverse proxy instead of the Vite dev server.
