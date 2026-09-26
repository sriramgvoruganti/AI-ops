from fastapi import APIRouter, HTTPException, status
from sqlalchemy import delete, select

from app.deps import CurrentUser, DbSession
from app.models import CartItem, Product, User
from app.schemas import CartItemIn, CartItemUpdate, CartOut

router = APIRouter(prefix="/cart", tags=["cart"])


def _cart(db: DbSession, user: User) -> CartOut:
    items = db.scalars(
        select(CartItem).where(CartItem.user_id == user.id).order_by(CartItem.id)
    ).all()
    subtotal = sum((i.product.price * i.quantity for i in items), start=0)
    return CartOut(items=items, subtotal=subtotal)


def _get_item(db: DbSession, user: User, item_id: int) -> CartItem:
    item = db.get(CartItem, item_id)
    if item is None or item.user_id != user.id:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Cart item not found")
    return item


def _check_stock(product: Product, quantity: int) -> None:
    if quantity > product.stock:
        raise HTTPException(
            status.HTTP_409_CONFLICT, f"Only {product.stock} of {product.name} in stock"
        )


@router.get("", response_model=CartOut)
def get_cart(user: CurrentUser, db: DbSession):
    return _cart(db, user)


@router.post("/items", response_model=CartOut)
def add_item(body: CartItemIn, user: CurrentUser, db: DbSession):
    product = db.get(Product, body.product_id)
    if product is None or not product.is_active:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Product not found")

    item = db.scalar(
        select(CartItem).where(CartItem.user_id == user.id, CartItem.product_id == product.id)
    )
    quantity = body.quantity + (item.quantity if item else 0)
    _check_stock(product, quantity)
    if item:
        item.quantity = quantity
    else:
        db.add(CartItem(user_id=user.id, product_id=product.id, quantity=quantity))
    db.commit()
    return _cart(db, user)


@router.patch("/items/{item_id}", response_model=CartOut)
def update_item(item_id: int, body: CartItemUpdate, user: CurrentUser, db: DbSession):
    item = _get_item(db, user, item_id)
    _check_stock(item.product, body.quantity)
    item.quantity = body.quantity
    db.commit()
    return _cart(db, user)


@router.delete("/items/{item_id}", response_model=CartOut)
def remove_item(item_id: int, user: CurrentUser, db: DbSession):
    db.delete(_get_item(db, user, item_id))
    db.commit()
    return _cart(db, user)


@router.delete("", response_model=CartOut)
def clear_cart(user: CurrentUser, db: DbSession):
    db.execute(delete(CartItem).where(CartItem.user_id == user.id))
    db.commit()
    return _cart(db, user)
