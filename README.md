# FreshMart — grocery chain storefront

| Layer    | Stack                                              |
| -------- | -------------------------------------------------- |
| Frontend | React 19 + TypeScript + Vite, React Router         |
| Backend  | FastAPI, SQLAlchemy 2, Alembic, JWT auth (bcrypt)  |
| Database | PostgreSQL 16                                      |
| Metrics  | Prometheus, postgres-exporter                      |

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
  prometheus.yml     Scrape config
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

## Before production

- Set a strong `JWT_SECRET` and change the admin password.
- Add a payment provider (checkout currently records orders as pay-on-delivery).
- Serve the frontend as a static build (`npm run build`) behind a reverse proxy instead of the Vite dev server.
