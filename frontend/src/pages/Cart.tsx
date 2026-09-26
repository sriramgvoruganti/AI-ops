import { useState } from "react";
import type { FormEvent } from "react";
import { Link, useNavigate } from "react-router-dom";
import { api, errorMessage, money } from "../api";
import { useCart } from "../cart";
import ProductImage from "../components/ProductImage";
import type { Order } from "../types";

export default function CartPage() {
  const { cart, update, remove, reset } = useCart();
  const navigate = useNavigate();
  const [address, setAddress] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  async function run(action: () => Promise<void>) {
    setError(null);
    try {
      await action();
    } catch (err) {
      setError(errorMessage(err));
    }
  }

  async function checkout(e: FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError(null);
    try {
      const order = await api<Order>("/orders", "POST", { shipping_address: address });
      reset();
      navigate("/orders", { state: { placed: order.id } });
    } catch (err) {
      setError(errorMessage(err));
    } finally {
      setBusy(false);
    }
  }

  if (cart.items.length === 0) {
    return (
      <div className="empty">
        <h1>Your cart is empty</h1>
        <p className="muted">
          <Link to="/">Browse the shop</Link> to add some groceries.
        </p>
      </div>
    );
  }

  return (
    <>
      <h1>Your cart</h1>
      {error && <p className="error">{error}</p>}
      <div className="cart-layout">
        <ul className="card cart-list">
          {cart.items.map((item) => (
            <li key={item.id} className="cart-row">
              <ProductImage product={item.product} size="sm" />
              <div className="cart-info">
                <strong>{item.product.name}</strong>
                <span className="muted small">
                  {money(item.product.price)} / {item.product.unit}
                </span>
              </div>
              <div className="stepper">
                <button
                  className="btn btn-small"
                  aria-label="Decrease quantity"
                  onClick={() =>
                    run(() =>
                      item.quantity > 1 ? update(item.id, item.quantity - 1) : remove(item.id),
                    )
                  }
                >
                  −
                </button>
                <span>{item.quantity}</span>
                <button
                  className="btn btn-small"
                  aria-label="Increase quantity"
                  onClick={() => run(() => update(item.id, item.quantity + 1))}
                >
                  +
                </button>
              </div>
              <span className="line-total">
                {money(Number(item.product.price) * item.quantity)}
              </span>
              <button className="link-button danger" onClick={() => run(() => remove(item.id))}>
                Remove
              </button>
            </li>
          ))}
        </ul>

        <form className="card summary" onSubmit={checkout}>
          <h2>Order summary</h2>
          <div className="summary-row">
            <span>Subtotal</span>
            <strong>{money(cart.subtotal)}</strong>
          </div>
          <div className="summary-row muted">
            <span>Delivery</span>
            <span>Free</span>
          </div>
          <label className="field">
            <span>Delivery address</span>
            <textarea
              className="input"
              rows={3}
              required
              minLength={5}
              value={address}
              onChange={(e) => setAddress(e.target.value)}
              placeholder="123 Main St, Springfield"
            />
          </label>
          <button className="btn btn-primary btn-block" disabled={busy}>
            {busy ? "Placing order…" : `Place order · ${money(cart.subtotal)}`}
          </button>
          <p className="muted small">Payment is collected on delivery.</p>
        </form>
      </div>
    </>
  );
}
