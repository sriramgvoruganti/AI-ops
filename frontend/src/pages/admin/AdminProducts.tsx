import { useEffect, useState } from "react";
import type { FormEvent } from "react";
import { api, errorMessage, money } from "../../api";
import type { Category, Product } from "../../types";

interface FormState {
  name: string;
  description: string;
  price: string;
  unit: string;
  image_url: string;
  stock: string;
  is_active: boolean;
  category_id: string;
}

function toForm(p: Product | null, categories: Category[]): FormState {
  return {
    name: p?.name ?? "",
    description: p?.description ?? "",
    price: p?.price ?? "",
    unit: p?.unit ?? "each",
    image_url: p?.image_url ?? "",
    stock: String(p?.stock ?? 0),
    is_active: p?.is_active ?? true,
    category_id: String(p?.category.id ?? categories[0]?.id ?? ""),
  };
}

export default function AdminProducts() {
  const [products, setProducts] = useState<Product[]>([]);
  const [categories, setCategories] = useState<Category[]>([]);
  const [filter, setFilter] = useState("");
  // null = form closed, "new" = creating, Product = editing that product.
  const [editing, setEditing] = useState<Product | "new" | null>(null);
  const [form, setForm] = useState<FormState>(() => toForm(null, []));
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    Promise.all([api<Product[]>("/admin/products"), api<Category[]>("/categories")])
      .then(([p, c]) => {
        setProducts(p);
        setCategories(c);
      })
      .catch((err) => setError(errorMessage(err)));
  }, []);

  function open(target: Product | "new") {
    setEditing(target);
    setForm(toForm(target === "new" ? null : target, categories));
    setError(null);
  }

  function set<K extends keyof FormState>(key: K, value: FormState[K]) {
    setForm((f) => ({ ...f, [key]: value }));
  }

  async function save(e: FormEvent) {
    e.preventDefault();
    setError(null);
    const body = { ...form, stock: Number(form.stock), category_id: Number(form.category_id) };
    try {
      if (editing === "new") {
        const created = await api<Product>("/admin/products", "POST", body);
        setProducts((prev) => [...prev, created].sort((a, b) => a.name.localeCompare(b.name)));
      } else if (editing) {
        const updated = await api<Product>(`/admin/products/${editing.id}`, "PATCH", body);
        setProducts((prev) => prev.map((p) => (p.id === updated.id ? updated : p)));
      }
      setEditing(null);
    } catch (err) {
      setError(errorMessage(err));
    }
  }

  async function destroy(product: Product) {
    if (!confirm(`Delete "${product.name}"? Past orders keep their line items.`)) return;
    try {
      await api(`/admin/products/${product.id}`, "DELETE");
      setProducts((prev) => prev.filter((p) => p.id !== product.id));
      if (editing !== "new" && editing?.id === product.id) setEditing(null);
    } catch (err) {
      setError(errorMessage(err));
    }
  }

  const visible = products.filter((p) => p.name.toLowerCase().includes(filter.toLowerCase()));

  return (
    <>
      <div className="toolbar">
        <input
          className="input"
          type="search"
          placeholder="Filter products…"
          value={filter}
          onChange={(e) => setFilter(e.target.value)}
        />
        <button className="btn btn-primary" onClick={() => open("new")} disabled={!categories.length}>
          New product
        </button>
      </div>
      {error && <p className="error">{error}</p>}

      {editing && (
        <form className="card form-grid" onSubmit={save}>
          <h2 className="span-2">{editing === "new" ? "New product" : `Edit ${editing.name}`}</h2>
          <label className="field">
            <span>Name</span>
            <input className="input" required value={form.name} onChange={(e) => set("name", e.target.value)} />
          </label>
          <label className="field">
            <span>Category</span>
            <select className="input" value={form.category_id} onChange={(e) => set("category_id", e.target.value)}>
              {categories.map((c) => (
                <option key={c.id} value={c.id}>
                  {c.name}
                </option>
              ))}
            </select>
          </label>
          <label className="field">
            <span>Price (USD)</span>
            <input
              className="input"
              type="number"
              step="0.01"
              min="0.01"
              required
              value={form.price}
              onChange={(e) => set("price", e.target.value)}
            />
          </label>
          <label className="field">
            <span>Unit</span>
            <input className="input" value={form.unit} onChange={(e) => set("unit", e.target.value)} />
          </label>
          <label className="field">
            <span>Stock</span>
            <input
              className="input"
              type="number"
              min="0"
              required
              value={form.stock}
              onChange={(e) => set("stock", e.target.value)}
            />
          </label>
          <label className="field">
            <span>Image URL (optional)</span>
            <input className="input" value={form.image_url} onChange={(e) => set("image_url", e.target.value)} />
          </label>
          <label className="field span-2">
            <span>Description</span>
            <textarea
              className="input"
              rows={2}
              value={form.description}
              onChange={(e) => set("description", e.target.value)}
            />
          </label>
          <label className="checkbox span-2">
            <input type="checkbox" checked={form.is_active} onChange={(e) => set("is_active", e.target.checked)} />
            Visible in shop
          </label>
          <div className="span-2 form-actions">
            <button type="button" className="btn" onClick={() => setEditing(null)}>
              Cancel
            </button>
            <button className="btn btn-primary">Save</button>
          </div>
        </form>
      )}

      <div className="card table-wrap">
        <table className="table">
          <thead>
            <tr>
              <th>Name</th>
              <th>Category</th>
              <th className="num">Price</th>
              <th className="num">Stock</th>
              <th>Status</th>
              <th />
            </tr>
          </thead>
          <tbody>
            {visible.map((p) => (
              <tr key={p.id}>
                <td>{p.name}</td>
                <td>{p.category.name}</td>
                <td className="num">
                  {money(p.price)} <span className="muted small">/ {p.unit}</span>
                </td>
                <td className={`num ${p.stock <= 10 ? "warning" : ""}`}>{p.stock}</td>
                <td>{p.is_active ? "Active" : <span className="muted">Hidden</span>}</td>
                <td className="actions">
                  <button className="link-button" onClick={() => open(p)}>
                    Edit
                  </button>
                  <button className="link-button danger" onClick={() => destroy(p)}>
                    Delete
                  </button>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </>
  );
}
