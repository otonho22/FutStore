export interface ProductSize { size: string; stock: number; }

export interface Product {
  id: string;
  name: string;
  team: string;
  description: string;
  price: number;
  imageUrl: string;
  images: string[];
  sizes: ProductSize[];
  category: string;
  salesCount?: number;
  active: boolean;
}

export interface Coupon {
  id: string;
  code: string;
  type: 'fixed' | 'percent';
  value: number;
  validUntil: string;
  active: boolean;
}

export interface CartItem {
  productId: string;
  name: string;
  size: string;
  unitPrice: number;
  quantity: number;
  imageUrl?: string;
}

export interface Address {
  fullName: string;
  street: string;
  number: string;
  complement?: string;
  city: string;
  state: string;
  zip: string;
}

export type OrderStatus = 'pendente' | 'pago' | 'enviado' | 'entregue' | 'cancelado';

export interface Order {
  id: string;
  userId: string;
  userEmail?: string | null;
  items: CartItem[];
  couponCode: string | null;
  subtotal: number;
  discount: number;
  shipping: number;
  total: number;
  address: Address;
  status: OrderStatus;
  statusHistory: { status: OrderStatus; at: any }[];
  trackingCode: string | null;
  createdAt: any;
}
