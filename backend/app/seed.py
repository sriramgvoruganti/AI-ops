"""Idempotent seed: creates the admin user and a starter catalog if they don't exist."""

from decimal import Decimal

from sqlalchemy import select

from app.config import settings
from app.db import SessionLocal
from app.models import Category, Product, User
from app.security import hash_password

CATALOG: dict[tuple[str, str], list[tuple[str, str, str, str, int]]] = {
    ("Fruits", "fruits"): [
        ("Bananas", "Ripe Cavendish bananas", "0.59", "lb", 200),
        ("Gala Apples", "Crisp and sweet", "1.99", "lb", 150),
        ("Strawberries", "Fresh California strawberries", "3.99", "1 lb pack", 60),
        ("Avocados", "Hass avocados, ready to eat", "1.25", "each", 90),
    ],
    ("Vegetables", "vegetables"): [
        ("Baby Spinach", "Pre-washed, 5 oz clamshell", "3.49", "5 oz", 70),
        ("Carrots", "Whole carrots", "1.29", "2 lb bag", 110),
        ("Roma Tomatoes", "Vine-ripened", "1.49", "lb", 120),
        ("Broccoli Crowns", "Fresh-cut crowns", "2.29", "lb", 80),
    ],
    ("Dairy & Eggs", "dairy-eggs"): [
        ("Whole Milk", "Grade A, vitamin D", "3.79", "gallon", 60),
        ("Large Eggs", "Cage-free, dozen", "4.49", "dozen", 75),
        ("Cheddar Cheese", "Sharp cheddar block", "4.99", "8 oz", 50),
        ("Greek Yogurt", "Plain, 2% milkfat", "5.49", "32 oz", 40),
    ],
    ("Bakery", "bakery"): [
        ("Sourdough Loaf", "Baked fresh daily", "5.99", "each", 30),
        ("Whole Wheat Bread", "100% whole wheat sandwich loaf", "3.49", "each", 45),
        ("Butter Croissants", "Pack of 4", "6.49", "4 ct", 25),
    ],
    ("Pantry", "pantry"): [
        ("Spaghetti", "Durum wheat pasta", "1.79", "16 oz", 100),
        ("Jasmine Rice", "Long grain", "7.99", "5 lb bag", 55),
        ("Extra Virgin Olive Oil", "Cold pressed", "9.99", "500 ml", 35),
        ("Peanut Butter", "Creamy, no added sugar", "3.99", "16 oz", 65),
    ],
}


def seed() -> None:
    with SessionLocal() as db:
        if not db.scalar(select(User).where(User.email == settings.admin_email)):
            db.add(
                User(
                    email=settings.admin_email,
                    full_name="Store Admin",
                    hashed_password=hash_password(settings.admin_password),
                    is_admin=True,
                )
            )
            print(f"Created admin user {settings.admin_email}")

        if db.scalar(select(Category).limit(1)) is None:
            for (name, slug), products in CATALOG.items():
                category = Category(name=name, slug=slug)
                db.add(category)
                for pname, desc, price, unit, stock in products:
                    db.add(
                        Product(
                            name=pname,
                            description=desc,
                            price=Decimal(price),
                            unit=unit,
                            stock=stock,
                            category=category,
                        )
                    )
            print("Seeded starter catalog")

        db.commit()


if __name__ == "__main__":
    seed()
