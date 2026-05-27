import { createContext, useContext, useEffect, useState, type ReactNode } from 'react';
import type { CartItem } from '../types';

const STORAGE_KEY = 'pf_cart_v1';

interface CartState {
  items: CartItem[];
  add: (item: CartItem) => void;
  remove: (productId: string, size: string) => void;
  setQuantity: (productId: string, size: string, qty: number) => void;
  clear: () => void;
  subtotal: number;
}

const CartContext = createContext<CartState | undefined>(undefined);

function read(): CartItem[] {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    return raw ? JSON.parse(raw) : [];
  } catch {
    return [];
  }
}

export function CartProvider({ children }: { children: ReactNode }) {
  const [items, setItems] = useState<CartItem[]>(() => read());

  useEffect(() => {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(items));
  }, [items]);

  function add(item: CartItem) {
    setItems((curr) => {
      const idx = curr.findIndex((i) => i.productId === item.productId && i.size === item.size);
      if (idx >= 0) {
        const copy = [...curr];
        copy[idx] = { ...copy[idx], quantity: copy[idx].quantity + item.quantity };
        return copy;
      }
      return [...curr, item];
    });
  }

  function remove(productId: string, size: string) {
    setItems((curr) => curr.filter((i) => !(i.productId === productId && i.size === size)));
  }

  function setQuantity(productId: string, size: string, qty: number) {
    setItems((curr) =>
      curr
        .map((i) =>
          i.productId === productId && i.size === size ? { ...i, quantity: Math.max(1, qty) } : i,
        )
        .filter((i) => i.quantity > 0),
    );
  }

  function clear() {
    setItems([]);
  }

  const subtotal = items.reduce((s, i) => s + i.unitPrice * i.quantity, 0);

  return (
    <CartContext.Provider value={{ items, add, remove, setQuantity, clear, subtotal }}>
      {children}
    </CartContext.Provider>
  );
}

export function useCart() {
  const ctx = useContext(CartContext);
  if (!ctx) throw new Error('useCart must be used inside CartProvider');
  return ctx;
}
