import { useEffect, useState } from "react";
import { Link, useLocation } from "react-router-dom";
import { api, errorMessage, money } from "../api";
import OrderStatusBadge from "../components/OrderStatusBadge";
import type { Order } from "../types";

export default function Orders() {
  const location = useLocation();
  const placedId = (location.state as { placed?: number } | null)?.placed;
  const [orders, setOrders] = useState<Order[] | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    api<Order[]>("/orders")
      .then(setOrders)
      .catch((err) => setError(errorMessage(err)));
  }, []);

  async function cancel(id: number) {
    if (!confirm("Cancel this order?")) return;
    try {
      const updated = await api<Order>(`/orders/${id}/cancel`, "POST");
      setOrders((prev) => prev?.map((o) => (o.id === id ? updated : o)) ?? null);
    } catch (err) {
      setError(errorMessage(err));
    }
  }

  return (
    <>
      <h1>Your orders</h1>
      {placedId && <p className="success">Order #{placedId} placed. Thanks for shopping with us!</p>}
      {error && <p className="error">{error}</p>}
      {orders === null && !error && <p className="muted">Loading…</p>}
      {orders?.length === 0 && (
        <p className="muted">
          No orders yet. <Link to="/">Start shopping</Link>
        </p>
      )}
      <div className="stack">
        {orders?.map((order) => (
          <article key={order.id} className="card order">
            <header className="order-header">
              <div>
                <strong>Order #{order.id}</strong>
                <span className="muted small"> · {new Date(order.created_at).toLocaleString()}</span>
              </div>
              <OrderStatusBadge status={order.status} />
            </header>
            <ul className="order-items">
              {order.items.map((item, idx) => (
                <li key={idx}>
                  <span>
                    {item.quantity} × {item.product_name}
                  </span>
                  <span>{money(Number(item.unit_price) * item.quantity)}</span>
                </li>
              ))}
            </ul>
            <footer className="order-footer">
              <span className="muted small">Deliver to: {order.shipping_address}</span>
              <div className="order-actions">
                {order.status === "pending" && (
                  <button className="link-button danger" onClick={() => cancel(order.id)}>
                    Cancel order
                  </button>
                )}
                <strong>{money(order.total)}</strong>
              </div>
            </footer>
          </article>
        ))}
      </div>
    </>
  );
}
