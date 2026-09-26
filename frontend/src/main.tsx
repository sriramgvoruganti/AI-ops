import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import { BrowserRouter, Navigate, Route, Routes } from "react-router-dom";
import { AuthProvider } from "./auth";
import { CartProvider } from "./cart";
import Layout from "./components/Layout";
import RequireAuth from "./components/RequireAuth";
import AuthForm from "./pages/AuthForm";
import CartPage from "./pages/Cart";
import Orders from "./pages/Orders";
import Shop from "./pages/Shop";
import AdminCategories from "./pages/admin/AdminCategories";
import AdminLayout from "./pages/admin/AdminLayout";
import AdminOrders from "./pages/admin/AdminOrders";
import AdminProducts from "./pages/admin/AdminProducts";
import "./styles.css";

createRoot(document.getElementById("root")!).render(
  <StrictMode>
    <BrowserRouter>
      <AuthProvider>
        <CartProvider>
          <Routes>
            <Route element={<Layout />}>
              <Route index element={<Shop />} />
              <Route path="login" element={<AuthForm mode="login" />} />
              <Route path="register" element={<AuthForm mode="register" />} />
              <Route
                path="cart"
                element={
                  <RequireAuth>
                    <CartPage />
                  </RequireAuth>
                }
              />
              <Route
                path="orders"
                element={
                  <RequireAuth>
                    <Orders />
                  </RequireAuth>
                }
              />
              <Route
                path="admin"
                element={
                  <RequireAuth admin>
                    <AdminLayout />
                  </RequireAuth>
                }
              >
                <Route index element={<AdminProducts />} />
                <Route path="categories" element={<AdminCategories />} />
                <Route path="orders" element={<AdminOrders />} />
              </Route>
              <Route path="*" element={<Navigate to="/" replace />} />
            </Route>
          </Routes>
        </CartProvider>
      </AuthProvider>
    </BrowserRouter>
  </StrictMode>,
);
