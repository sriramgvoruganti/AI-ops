from datetime import datetime
from decimal import Decimal

from pydantic import BaseModel, ConfigDict, EmailStr, Field

from app.models import OrderStatus


class ORMModel(BaseModel):
    model_config = ConfigDict(from_attributes=True)


# --- Auth ---


class UserCreate(BaseModel):
    email: EmailStr
    # bcrypt only uses the first 72 bytes of a password.
    password: str = Field(min_length=8, max_length=72)
    full_name: str = Field(min_length=1, max_length=255)


class LoginIn(BaseModel):
    email: str
    password: str


class UserOut(ORMModel):
    id: int
    email: str
    full_name: str
    is_admin: bool


class Token(BaseModel):
    access_token: str
    token_type: str = "bearer"
    user: UserOut


# --- Catalog ---


class CategoryIn(BaseModel):
    name: str = Field(min_length=1, max_length=100)
    slug: str = Field(min_length=1, max_length=100, pattern=r"^[a-z0-9-]+$")


class CategoryOut(ORMModel, CategoryIn):
    id: int


class ProductIn(BaseModel):
    name: str = Field(min_length=1, max_length=200)
    description: str = ""
    price: Decimal = Field(gt=0, max_digits=10, decimal_places=2)
    unit: str = Field(default="each", max_length=30)
    image_url: str = Field(default="", max_length=500)
    stock: int = Field(default=0, ge=0)
    is_active: bool = True
    category_id: int


class ProductUpdate(BaseModel):
    name: str | None = Field(default=None, min_length=1, max_length=200)
    description: str | None = None
    price: Decimal | None = Field(default=None, gt=0, max_digits=10, decimal_places=2)
    unit: str | None = Field(default=None, max_length=30)
    image_url: str | None = Field(default=None, max_length=500)
    stock: int | None = Field(default=None, ge=0)
    is_active: bool | None = None
    category_id: int | None = None


class ProductOut(ORMModel):
    id: int
    name: str
    description: str
    price: Decimal
    unit: str
    image_url: str
    stock: int
    is_active: bool
    category: CategoryOut


class ProductPage(BaseModel):
    items: list[ProductOut]
    total: int


# --- Cart ---


class CartItemIn(BaseModel):
    product_id: int
    quantity: int = Field(default=1, ge=1, le=99)


class CartItemUpdate(BaseModel):
    quantity: int = Field(ge=1, le=99)


class CartItemOut(ORMModel):
    id: int
    quantity: int
    product: ProductOut


class CartOut(BaseModel):
    items: list[CartItemOut]
    subtotal: Decimal


# --- Orders ---


class CheckoutIn(BaseModel):
    shipping_address: str = Field(min_length=5, max_length=1000)


class OrderItemOut(ORMModel):
    product_id: int | None
    product_name: str
    unit_price: Decimal
    quantity: int


class OrderOut(ORMModel):
    id: int
    status: OrderStatus
    total: Decimal
    shipping_address: str
    created_at: datetime
    items: list[OrderItemOut]


class AdminOrderOut(OrderOut):
    user: UserOut


class OrderStatusUpdate(BaseModel):
    status: OrderStatus
