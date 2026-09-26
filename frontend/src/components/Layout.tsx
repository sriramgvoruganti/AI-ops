import { Link, NavLink, Outlet } from "react-router-dom";
import { useAuth } from "../auth";
import { useCart } from "../cart";

export default function Layout() {
  const { user, logout } = useAuth();
  const { count } = useCart();

  return (
    <>
      <header className="header">
        <div className="container header-inner">
          <Link to="/" className="logo">
            🥕 FreshMart
          </Link>
          <nav className="nav">
            <NavLink to="/" end>
              Shop
            </NavLink>
            {user && <NavLink to="/orders">Orders</NavLink>}
            {user?.is_admin && <NavLink to="/admin">Admin</NavLink>}
            <NavLink to="/cart" className="cart-link">
              Cart{count > 0 && <span className="badge">{count}</span>}
            </NavLink>
            {user ? (
              <button className="link-button" onClick={logout} title={user.email}>
                Log out
              </button>
            ) : (
              <NavLink to="/login">Log in</NavLink>
            )}
          </nav>
        </div>
      </header>
      <main className="container main">
        <Outlet />
      </main>
      <footer className="footer container">© FreshMart · Fresh groceries, delivered.</footer>
    </>
  );
}
