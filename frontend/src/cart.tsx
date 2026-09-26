import { createContext, useCallback, useContext, useEffect, useMemo, useState } from "react";
import type { ReactNode } from "react";
import { api } from "./api";
import { useAuth } from "./auth";
import type { Cart } from "./types";

const EMPTY_CART: Cart = { items: [], subtotal: "0" };

interface CartContextValue {
  cart: Cart;
  count: number;
  add: (productId: number, quantity?: number) => Promise<void>;
  update: (itemId: number, quantity: number) => Promise<void>;
  remove: (itemId: number) => Promise<void>;
  reset: () => void;
}

const CartContext = createContext<CartContextValue | null>(null);

export function CartProvider({ children }: { children: ReactNode }) {
  const { user } = useAuth();
  const [cart, setCart] = useState<Cart>(EMPTY_CART);

  useEffect(() => {
    if (!user) {
      setCart(EMPTY_CART);
      return;
    }
    api<Cart>("/cart").then(setCart).catch(() => setCart(EMPTY_CART));
  }, [user]);

  const add = useCallback(async (product_id: number, quantity = 1) => {
    setCart(await api<Cart>("/cart/items", "POST", { product_id, quantity }));
  }, []);

  const update = useCallback(async (itemId: number, quantity: number) => {
    setCart(await api<Cart>(`/cart/items/${itemId}`, "PATCH", { quantity }));
  }, []);

  const remove = useCallback(async (itemId: number) => {
    setCart(await api<Cart>(`/cart/items/${itemId}`, "DELETE"));
  }, []);

  // Checkout empties the cart on the server; mirror that locally.
  const reset = useCallback(() => setCart(EMPTY_CART), []);

  const value = useMemo(
    () => ({
      cart,
      count: cart.items.reduce((n, i) => n + i.quantity, 0),
      add,
      update,
      remove,
      reset,
    }),
    [cart, add, update, remove, reset],
  );

  return <CartContext.Provider value={value}>{children}</CartContext.Provider>;
}

export function useCart(): CartContextValue {
  const ctx = useContext(CartContext);
  if (!ctx) throw new Error("useCart must be used inside CartProvider");
  return ctx;
}
