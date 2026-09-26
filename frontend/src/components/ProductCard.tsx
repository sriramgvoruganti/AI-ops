import { useState } from "react";
import { useNavigate } from "react-router-dom";
import { errorMessage, money } from "../api";
import { useAuth } from "../auth";
import { useCart } from "../cart";
import type { Product } from "../types";
import ProductImage from "./ProductImage";

export default function ProductCard({ product }: { product: Product }) {
  const { user } = useAuth();
  const { cart, add } = useCart();
  const navigate = useNavigate();
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const inCart = cart.items.find((i) => i.product.id === product.id)?.quantity ?? 0;
  const outOfStock = product.stock === 0;

  async function handleAdd() {
    if (!user) {
      navigate("/login", { state: { from: "/" } });
      return;
    }
    setBusy(true);
    setError(null);
    try {
      await add(product.id);
    } catch (err) {
      setError(errorMessage(err));
    } finally {
      setBusy(false);
    }
  }

  return (
    <article className="card product-card">
      <ProductImage product={product} />
      <div className="product-body">
        <span className="eyebrow">{product.category.name}</span>
        <h3>{product.name}</h3>
        <p className="muted small">{product.description}</p>
        <div className="product-footer">
          <div>
            <span className="price">{money(product.price)}</span>
            <span className="muted small"> / {product.unit}</span>
          </div>
          <button className="btn btn-primary" onClick={handleAdd} disabled={busy || outOfStock}>
            {outOfStock ? "Sold out" : inCart ? `Add (${inCart})` : "Add"}
          </button>
        </div>
        {product.stock > 0 && product.stock <= 10 && (
          <p className="warning small">Only {product.stock} left</p>
        )}
        {error && <p className="error small">{error}</p>}
      </div>
    </article>
  );
}
