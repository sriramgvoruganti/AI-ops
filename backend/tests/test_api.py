from decimal import Decimal

from app.config import settings
from tests.conftest import auth_headers


def register(client, email="shopper@example.com"):
    res = client.post(
        "/api/auth/register",
        json={"email": email, "password": "password123", "full_name": "Sam Shopper"},
    )
    assert res.status_code == 201, res.text
    return {"Authorization": f"Bearer {res.json()['access_token']}"}


def first_product(client, **params):
    return client.get("/api/products", params=params).json()["items"][0]


def test_catalog_search_and_filter(client):
    assert len(client.get("/api/categories").json()) == 5
    page = client.get("/api/products", params={"category": "bakery"}).json()
    assert page["total"] == 3
    assert all(p["category"]["slug"] == "bakery" for p in page["items"])
    assert client.get("/api/products", params={"q": "banana"}).json()["total"] == 1


def test_register_rejects_duplicate_email(client):
    register(client)
    res = client.post(
        "/api/auth/register",
        json={"email": "SHOPPER@example.com", "password": "password123", "full_name": "X"},
    )
    assert res.status_code == 409


def test_cart_requires_auth(client):
    assert client.get("/api/cart").status_code == 401


def test_checkout_decrements_stock_and_cancel_restocks(client):
    headers = register(client)
    product = first_product(client, q="Bananas")

    cart = client.post(
        "/api/cart/items", json={"product_id": product["id"], "quantity": 3}, headers=headers
    ).json()
    assert Decimal(cart["subtotal"]) == Decimal(product["price"]) * 3

    res = client.post("/api/orders", json={"shipping_address": "1 Main St"}, headers=headers)
    assert res.status_code == 201, res.text
    order = res.json()
    assert order["status"] == "pending"
    assert Decimal(order["total"]) == Decimal(product["price"]) * 3
    assert client.get("/api/cart", headers=headers).json()["items"] == []
    assert client.get(f"/api/products/{product['id']}").json()["stock"] == product["stock"] - 3

    res = client.post(f"/api/orders/{order['id']}/cancel", headers=headers)
    assert res.json()["status"] == "cancelled"
    assert client.get(f"/api/products/{product['id']}").json()["stock"] == product["stock"]


def test_cannot_add_more_than_stock(client):
    headers = register(client)
    product = first_product(client, q="Butter Croissants")
    res = client.post(
        "/api/cart/items",
        json={"product_id": product["id"], "quantity": product["stock"] + 1},
        headers=headers,
    )
    assert res.status_code == 409


def test_admin_endpoints_require_admin(client):
    headers = register(client)
    assert client.get("/api/admin/products", headers=headers).status_code == 403


def test_admin_manages_products_and_orders(client):
    admin = auth_headers(client, settings.admin_email, settings.admin_password)
    category_id = client.get("/api/categories").json()[0]["id"]

    res = client.post(
        "/api/admin/products",
        json={"name": "Kiwi", "price": "0.79", "stock": 5, "category_id": category_id},
        headers=admin,
    )
    assert res.status_code == 201, res.text
    kiwi = res.json()

    res = client.patch(
        f"/api/admin/products/{kiwi['id']}", json={"is_active": False}, headers=admin
    )
    assert res.json()["is_active"] is False
    assert client.get(f"/api/products/{kiwi['id']}").status_code == 404

    shopper = register(client)
    product = first_product(client)
    client.post("/api/cart/items", json={"product_id": product["id"]}, headers=shopper)
    order = client.post(
        "/api/orders", json={"shipping_address": "1 Main St"}, headers=shopper
    ).json()

    res = client.patch(
        f"/api/admin/orders/{order['id']}", json={"status": "delivered"}, headers=admin
    )
    assert res.json()["status"] == "delivered"
    res = client.patch(
        f"/api/admin/orders/{order['id']}", json={"status": "cancelled"}, headers=admin
    )
    assert res.status_code == 409
