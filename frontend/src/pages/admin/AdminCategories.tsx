import { useEffect, useState } from "react";
import type { FormEvent } from "react";
import { api, errorMessage } from "../../api";
import type { Category } from "../../types";

function slugify(name: string): string {
  return name
    .toLowerCase()
    .replace(/&/g, " ")
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "");
}

export default function AdminCategories() {
  const [categories, setCategories] = useState<Category[]>([]);
  const [name, setName] = useState("");
  const [editingId, setEditingId] = useState<number | null>(null);
  const [editName, setEditName] = useState("");
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    api<Category[]>("/categories")
      .then(setCategories)
      .catch((err) => setError(errorMessage(err)));
  }, []);

  const sorted = (list: Category[]) => [...list].sort((a, b) => a.name.localeCompare(b.name));

  async function create(e: FormEvent) {
    e.preventDefault();
    setError(null);
    try {
      const created = await api<Category>("/admin/categories", "POST", { name, slug: slugify(name) });
      setCategories((prev) => sorted([...prev, created]));
      setName("");
    } catch (err) {
      setError(errorMessage(err));
    }
  }

  async function rename(id: number) {
    setError(null);
    try {
      const updated = await api<Category>(`/admin/categories/${id}`, "PUT", {
        name: editName,
        slug: slugify(editName),
      });
      setCategories((prev) => sorted(prev.map((c) => (c.id === id ? updated : c))));
      setEditingId(null);
    } catch (err) {
      setError(errorMessage(err));
    }
  }

  async function destroy(category: Category) {
    if (!confirm(`Delete category "${category.name}"?`)) return;
    setError(null);
    try {
      await api(`/admin/categories/${category.id}`, "DELETE");
      setCategories((prev) => prev.filter((c) => c.id !== category.id));
    } catch (err) {
      setError(errorMessage(err));
    }
  }

  return (
    <>
      <form className="toolbar" onSubmit={create}>
        <input
          className="input"
          placeholder="New category name"
          required
          value={name}
          onChange={(e) => setName(e.target.value)}
        />
        <button className="btn btn-primary" disabled={!slugify(name)}>
          Add category
        </button>
      </form>
      {error && <p className="error">{error}</p>}

      <div className="card table-wrap">
        <table className="table">
          <thead>
            <tr>
              <th>Name</th>
              <th>Slug</th>
              <th />
            </tr>
          </thead>
          <tbody>
            {categories.map((c) => (
              <tr key={c.id}>
                <td>
                  {editingId === c.id ? (
                    <input
                      className="input input-inline"
                      autoFocus
                      value={editName}
                      onChange={(e) => setEditName(e.target.value)}
                      onKeyDown={(e) => {
                        if (e.key === "Enter") rename(c.id);
                        if (e.key === "Escape") setEditingId(null);
                      }}
                    />
                  ) : (
                    c.name
                  )}
                </td>
                <td className="muted">{c.slug}</td>
                <td className="actions">
                  {editingId === c.id ? (
                    <>
                      <button className="link-button" onClick={() => rename(c.id)}>
                        Save
                      </button>
                      <button className="link-button" onClick={() => setEditingId(null)}>
                        Cancel
                      </button>
                    </>
                  ) : (
                    <>
                      <button
                        className="link-button"
                        onClick={() => {
                          setEditingId(c.id);
                          setEditName(c.name);
                        }}
                      >
                        Rename
                      </button>
                      <button className="link-button danger" onClick={() => destroy(c)}>
                        Delete
                      </button>
                    </>
                  )}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </>
  );
}
