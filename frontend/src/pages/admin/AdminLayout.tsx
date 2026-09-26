import { NavLink, Outlet } from "react-router-dom";

export default function AdminLayout() {
  return (
    <>
      <h1>Store admin</h1>
      <nav className="tabs">
        <NavLink to="/admin" end>
          Products
        </NavLink>
        <NavLink to="/admin/categories">Categories</NavLink>
        <NavLink to="/admin/orders">Orders</NavLink>
      </nav>
      <Outlet />
    </>
  );
}
