from fastapi import APIRouter, HTTPException, status
from sqlalchemy import delete, select

from app.deps import CurrentUser, DbSession
from app.inventory import lock_products, restock
from app.models import CartItem, Order, OrderItem, OrderStatus, User
from app.schemas import CheckoutIn, OrderOut

router = APIRouter(prefix="/orders", tags=["orders"])


def _get_order(db: DbSession, user: User, order_id: int) -> Order:
    order = db.get(Order, order_id)
    if order is None or order.user_id != user.id:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Order not found")
    return order


@router.post("", response_model=OrderOut, status_code=status.HTTP_201_CREATED)
def checkout(body: CheckoutIn, user: CurrentUser, db: DbSession):
    cart = db.scalars(select(CartItem).where(CartItem.user_id == user.id)).all()
    if not cart:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "Your cart is empty")

    # Lock the products so concurrent checkouts can't oversell stock.
    products = lock_products(db, [i.product_id for i in cart])
    order = Order(user_id=user.id, shipping_address=body.shipping_address.strip(), total=0)
    for line in cart:
        product = products[line.product_id]
        if not product.is_active:
            raise HTTPException(status.HTTP_409_CONFLICT, f"{product.name} is no longer available")
        if line.quantity > product.stock:
            raise HTTPException(
                status.HTTP_409_CONFLICT, f"Only {product.stock} of {product.name} in stock"
            )
        product.stock -= line.quantity
        order.items.append(
            OrderItem(
                product_id=product.id,
                product_name=product.name,
                unit_price=product.price,
                quantity=line.quantity,
            )
        )
        order.total += product.price * line.quantity

    db.add(order)
    db.execute(delete(CartItem).where(CartItem.user_id == user.id))
    db.commit()
    db.refresh(order)  # load server-generated created_at
    return order


@router.get("", response_model=list[OrderOut])
def list_orders(user: CurrentUser, db: DbSession):
    return db.scalars(
        select(Order).where(Order.user_id == user.id).order_by(Order.created_at.desc(), Order.id.desc())
    ).all()


@router.get("/{order_id}", response_model=OrderOut)
def get_order(order_id: int, user: CurrentUser, db: DbSession):
    return _get_order(db, user, order_id)


@router.post("/{order_id}/cancel", response_model=OrderOut)
def cancel_order(order_id: int, user: CurrentUser, db: DbSession):
    order = _get_order(db, user, order_id)
    if order.status != OrderStatus.pending:
        raise HTTPException(status.HTTP_409_CONFLICT, "Only pending orders can be cancelled")
    restock(db, order)
    order.status = OrderStatus.cancelled
    db.commit()
    return order
