export interface User {
  id: number;
  email: string;
  full_name: string;
  is_admin: boolean;
}

export interface Category {
  id: number;
  name: string;
  slug: string;
}

// Money values arrive as decimal strings (e.g. "3.99") to avoid float rounding.
export interface Product {
  id: number;
  name: string;
  description: string;
  price: string;
  unit: string;
  image_url: string;
  stock: number;
  is_active: boolean;
  category: Category;
}

export interface ProductPage {
  items: Product[];
  total: number;
}

export interface CartItem {
  id: number;
  quantity: number;
  product: Product;
}

export interface Cart {
  items: CartItem[];
  subtotal: string;
}

export const ORDER_STATUSES = [
  "pending",
  "confirmed",
  "out_for_delivery",
  "delivered",
  "cancelled",
] as const;

export type OrderStatus = (typeof ORDER_STATUSES)[number];

export interface OrderItem {
  product_id: number | null;
  product_name: string;
  unit_price: string;
  quantity: number;
}

export interface Order {
  id: number;
  status: OrderStatus;
  total: string;
  shipping_address: string;
  created_at: string;
  items: OrderItem[];
}

export interface AdminOrder extends Order {
  user: User;
}

export interface AuthResponse {
  access_token: string;
  user: User;
}
