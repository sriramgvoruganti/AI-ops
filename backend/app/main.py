from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from prometheus_fastapi_instrumentator import Instrumentator

from app.config import settings
from app.routers import admin, auth, cart, catalog, orders

app = FastAPI(title="FreshMart API", docs_url="/api/docs", openapi_url="/api/openapi.json")

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origins,
    allow_methods=["*"],
    allow_headers=["*"],
)

for module in (auth, catalog, cart, orders, admin):
    app.include_router(module.router, prefix="/api")

# HTTP request metrics, scraped by Prometheus at /metrics. Deliberately outside /api so the
# frontend dev proxy doesn't expose it publicly.
Instrumentator(excluded_handlers=["/metrics", "/api/health"]).instrument(app).expose(
    app, include_in_schema=False
)


@app.get("/api/health", tags=["health"])
def health():
    return {"status": "ok"}
