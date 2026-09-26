import { useEffect, useState } from "react";
import { api, errorMessage, money } from "../../api";
import OrderStatusBadge, { STATUS_LABEL } from "../../components/OrderStatusBadge";
import { ORDER_STATUSES } from "../../types";
import type { AdminOrder, OrderStatus } from "../../types";

const FINAL: OrderStatus[] = ["delivered", "cancelled"];

export default function AdminOrders() {
  const [orders, setOrders] = useState<AdminOrder[]>([]);
  const [status, setStatus] = useState<OrderStatus | "">("");
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    setError(null);
    api<AdminOrder[]>(`/admin/orders${status ? `?status=${status}` : ""}`)
      .then(setOrders)
      .catch((err) => setError(errorMessage(err)));
  }, [status]);

  async function changeStatus(order: AdminOrder, next: OrderStatus) {
    if (next === "cancelled" && !confirm(`Cancel order #${order.id}? Items will be restocked.`)) return;
    setError(null);
    try {
      const updated = await api<AdminOrder>(`/admin/orders/${order.id}`, "PATCH", { status: next });
      setOrders((prev) => prev.map((o) => (o.id === updated.id ? updated : o)));
    } catch (err) {
      setError(errorMessage(err));
    }
  }

  return (
    <>
      <div className="toolbar">
        <select
          className="input"
          value={status}
          onChange={(e) => setStatus(e.target.value as OrderStatus | "")}
          aria-label="Filter by status"
        >
          <option value="">All statuses</option>
          {ORDER_STATUSES.map((s) => (
            <option key={s} value={s}>
              {STATUS_LABEL[s]}
            </option>
          ))}
        </select>
      </div>
      {error && <p className="error">{error}</p>}
      {orders.length === 0 && <p className="muted">No orders.</p>}

      {orders.length > 0 && (
        <div className="card table-wrap">
          <table className="table">
            <thead>
              <tr>
                <th>Order</th>
                <th>Customer</th>
                <th>Items</th>
                <th className="num">Total</th>
                <th>Status</th>
                <th>Update</th>
              </tr>
            </thead>
            <tbody>
              {orders.map((o) => (
                <tr key={o.id}>
                  <td>
                    #{o.id}
                    <div className="muted small">{new Date(o.created_at).toLocaleString()}</div>
                  </td>
                  <td>
                    {o.user.full_name}
                    <div className="muted small">{o.user.email}</div>
                  </td>
                  <td className="small">
                    {o.items.map((i) => `${i.quantity} × ${i.product_name}`).join(", ")}
                    <div className="muted">{o.shipping_address}</div>
                  </td>
                  <td className="num">{money(o.total)}</td>
                  <td>
                    <OrderStatusBadge status={o.status} />
                  </td>
                  <td>
                    {FINAL.includes(o.status) ? (
                      <span className="muted small">Final</span>
                    ) : (
                      <select
                        className="input input-inline"
                        value={o.status}
                        onChange={(e) => changeStatus(o, e.target.value as OrderStatus)}
                        aria-label={`Update status of order ${o.id}`}
                      >
                        {ORDER_STATUSES.map((s) => (
                          <option key={s} value={s}>
                            {STATUS_LABEL[s]}
                          </option>
                        ))}
                      </select>
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </>
  );
}
