from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models import Order, Product


def lock_products(db: Session, product_ids: list[int]) -> dict[int, Product]:
    """Row-lock products (in id order, to avoid deadlocks) and return fresh copies."""
    products = db.scalars(
        select(Product)
        .where(Product.id.in_(product_ids))
        .order_by(Product.id)
        .with_for_update(of=Product)
        .execution_options(populate_existing=True)
    ).unique()
    return {p.id: p for p in products}


def restock(db: Session, order: Order) -> None:
    """Return an order's items to inventory (used when an order is cancelled)."""
    ids = [i.product_id for i in order.items if i.product_id is not None]
    products = lock_products(db, ids)
    for item in order.items:
        if item.product_id in products:
            products[item.product_id].stock += item.quantity
