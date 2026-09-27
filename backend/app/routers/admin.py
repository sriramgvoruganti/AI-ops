from typing import Annotated

from fastapi import APIRouter, HTTPException, Query, Response, status
from sqlalchemy import exists, select
from sqlalchemy.exc import IntegrityError

from app.deps import AdminUser, DbSession
from app.inventory import restock
from app.metrics import ORDERS_CANCELLED
from app.models import Category, Order, OrderStatus, Product
from app.schemas import (
    AdminOrderOut,
    CategoryIn,
    CategoryOut,
    OrderStatusUpdate,
    ProductIn,
    ProductOut,
    ProductUpdate,
)

router = APIRouter(prefix="/admin", tags=["admin"])

FINAL_STATUSES = {OrderStatus.delivered, OrderStatus.cancelled}


def _commit_or_conflict(db: DbSession, message: str) -> None:
    try:
        db.commit()
    except IntegrityError:
        db.rollback()
        raise HTTPException(status.HTTP_409_CONFLICT, message)


def _ensure_category(db: DbSession, category_id: int) -> None:
    if db.get(Category, category_id) is None:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_ENTITY, "Category does not exist")


# --- Categories ---


@router.post("/categories", response_model=CategoryOut, status_code=status.HTTP_201_CREATED)
def create_category(body: CategoryIn, _: AdminUser, db: DbSession):
    category = Category(**body.model_dump())
    db.add(category)
    _commit_or_conflict(db, "A category with that name or slug already exists")
    return category


@router.put("/categories/{category_id}", response_model=CategoryOut)
def update_category(category_id: int, body: CategoryIn, _: AdminUser, db: DbSession):
    category = db.get(Category, category_id)
    if category is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Category not found")
    category.name, category.slug = body.name, body.slug
    _commit_or_conflict(db, "A category with that name or slug already exists")
    return category


@router.delete("/categories/{category_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_category(category_id: int, _: AdminUser, db: DbSession):
    category = db.get(Category, category_id)
    if category is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Category not found")
    if db.scalar(select(exists().where(Product.category_id == category_id))):
        raise HTTPException(status.HTTP_409_CONFLICT, "Move or delete this category's products first")
    db.delete(category)
    db.commit()
    return Response(status_code=status.HTTP_204_NO_CONTENT)


# --- Products ---


@router.get("/products", response_model=list[ProductOut])
def list_all_products(_: AdminUser, db: DbSession):
    return db.scalars(select(Product).order_by(Product.name)).all()


@router.post("/products", response_model=ProductOut, status_code=status.HTTP_201_CREATED)
def create_product(body: ProductIn, _: AdminUser, db: DbSession):
    _ensure_category(db, body.category_id)
    product = Product(**body.model_dump())
    db.add(product)
    db.commit()
    db.refresh(product)
    return product


@router.patch("/products/{product_id}", response_model=ProductOut)
def update_product(product_id: int, body: ProductUpdate, _: AdminUser, db: DbSession):
    product = db.get(Product, product_id)
    if product is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Product not found")
    changes = body.model_dump(exclude_unset=True)
    if changes.get("category_id") is not None:
        _ensure_category(db, changes["category_id"])
    for field, value in changes.items():
        if value is not None:
            setattr(product, field, value)
    db.commit()
    db.refresh(product)
    return product


@router.delete("/products/{product_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_product(product_id: int, _: AdminUser, db: DbSession):
    product = db.get(Product, product_id)
    if product is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Product not found")
    db.delete(product)
    db.commit()
    return Response(status_code=status.HTTP_204_NO_CONTENT)


# --- Orders ---


@router.get("/orders", response_model=list[AdminOrderOut])
def list_all_orders(
    _: AdminUser,
    db: DbSession,
    order_status: Annotated[OrderStatus | None, Query(alias="status")] = None,
):
    query = select(Order).order_by(Order.created_at.desc(), Order.id.desc())
    if order_status:
        query = query.where(Order.status == order_status)
    return db.scalars(query).all()


@router.patch("/orders/{order_id}", response_model=AdminOrderOut)
def update_order_status(order_id: int, body: OrderStatusUpdate, _: AdminUser, db: DbSession):
    order = db.get(Order, order_id)
    if order is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Order not found")
    if order.status in FINAL_STATUSES:
        raise HTTPException(status.HTTP_409_CONFLICT, f"Order is already {order.status}")
    if body.status == OrderStatus.cancelled:
        restock(db, order)
    order.status = body.status
    db.commit()
    if body.status == OrderStatus.cancelled:
        ORDERS_CANCELLED.labels(cancelled_by="admin").inc()
    return order
