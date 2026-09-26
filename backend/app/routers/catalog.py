from typing import Annotated

from fastapi import APIRouter, HTTPException, Query, status
from sqlalchemy import func, or_, select

from app.deps import DbSession
from app.models import Category, Product
from app.schemas import CategoryOut, ProductOut, ProductPage

router = APIRouter(tags=["catalog"])


@router.get("/categories", response_model=list[CategoryOut])
def list_categories(db: DbSession):
    return db.scalars(select(Category).order_by(Category.name)).all()


@router.get("/products", response_model=ProductPage)
def list_products(
    db: DbSession,
    q: str | None = None,
    category: Annotated[str | None, Query(description="Category slug")] = None,
    limit: Annotated[int, Query(ge=1, le=100)] = 24,
    offset: Annotated[int, Query(ge=0)] = 0,
):
    query = select(Product).where(Product.is_active.is_(True))
    if q:
        pattern = f"%{q.strip()}%"
        query = query.where(or_(Product.name.ilike(pattern), Product.description.ilike(pattern)))
    if category:
        query = query.join(Product.category).where(Category.slug == category)

    total = db.scalar(select(func.count()).select_from(query.subquery()))
    items = db.scalars(query.order_by(Product.name).limit(limit).offset(offset)).all()
    return ProductPage(items=items, total=total)


@router.get("/products/{product_id}", response_model=ProductOut)
def get_product(product_id: int, db: DbSession):
    product = db.get(Product, product_id)
    if product is None or not product.is_active:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Product not found")
    return product
