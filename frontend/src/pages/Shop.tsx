import { useEffect, useState } from "react";
import { useSearchParams } from "react-router-dom";
import { api, errorMessage } from "../api";
import ProductCard from "../components/ProductCard";
import type { Category, Product, ProductPage } from "../types";

const PAGE_SIZE = 24;

export default function Shop() {
  const [params, setParams] = useSearchParams();
  const q = params.get("q") ?? "";
  const category = params.get("category") ?? "";

  const [search, setSearch] = useState(q);
  const [categories, setCategories] = useState<Category[]>([]);
  const [products, setProducts] = useState<Product[]>([]);
  const [total, setTotal] = useState(0);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    api<Category[]>("/categories").then(setCategories).catch(() => setCategories([]));
  }, []);

  // Debounce the search box into the URL.
  useEffect(() => {
    const t = setTimeout(() => {
      if (search.trim() === q) return;
      setParams((prev) => {
        const next = new URLSearchParams(prev);
        if (search.trim()) next.set("q", search.trim());
        else next.delete("q");
        return next;
      });
    }, 300);
    return () => clearTimeout(t);
  }, [search, q, setParams]);

  async function load(offset: number) {
    const query = new URLSearchParams({ limit: String(PAGE_SIZE), offset: String(offset) });
    if (q) query.set("q", q);
    if (category) query.set("category", category);
    return api<ProductPage>(`/products?${query}`);
  }

  useEffect(() => {
    let cancelled = false;
    setLoading(true);
    setError(null);
    load(0)
      .then((page) => {
        if (cancelled) return;
        setProducts(page.items);
        setTotal(page.total);
      })
      .catch((err) => !cancelled && setError(errorMessage(err)))
      .finally(() => !cancelled && setLoading(false));
    return () => {
      cancelled = true;
    };
  }, [q, category]);

  async function loadMore() {
    setLoading(true);
    try {
      const page = await load(products.length);
      setProducts((prev) => [...prev, ...page.items]);
      setTotal(page.total);
    } catch (err) {
      setError(errorMessage(err));
    } finally {
      setLoading(false);
    }
  }

  function selectCategory(slug: string) {
    setParams((prev) => {
      const next = new URLSearchParams(prev);
      if (slug) next.set("category", slug);
      else next.delete("category");
      return next;
    });
  }

  return (
    <>
      <section className="hero">
        <h1>Fresh groceries, delivered to your door</h1>
        <p className="muted">Farm-fresh produce, dairy, bakery and pantry staples.</p>
        <input
          className="input search"
          type="search"
          placeholder="Search products…"
          value={search}
          onChange={(e) => setSearch(e.target.value)}
          aria-label="Search products"
        />
      </section>

      <div className="chips" role="tablist" aria-label="Categories">
        <button className={`chip ${category === "" ? "active" : ""}`} onClick={() => selectCategory("")}>
          All
        </button>
        {categories.map((c) => (
          <button
            key={c.id}
            className={`chip ${category === c.slug ? "active" : ""}`}
            onClick={() => selectCategory(c.slug)}
          >
            {c.name}
          </button>
        ))}
      </div>

      {error && <p className="error">{error}</p>}
      {!loading && products.length === 0 && !error && (
        <p className="muted empty">No products match your search.</p>
      )}

      <div className="grid">
        {products.map((p) => (
          <ProductCard key={p.id} product={p} />
        ))}
      </div>

      {loading && <p className="muted center">Loading…</p>}
      {!loading && products.length < total && (
        <div className="center">
          <button className="btn" onClick={loadMore}>
            Load more
          </button>
        </div>
      )}
    </>
  );
}
