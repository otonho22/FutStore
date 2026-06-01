import { useState, type MouseEvent } from 'react';
import { useCart } from '../context/CartContext';
import type { Product } from '../types';

export default function QuickAdd({ product }: { product: Product }) {
  const { add } = useCart();
  const [feedback, setFeedback] = useState<string | null>(null);

  function handleClick(e: MouseEvent) {
    e.preventDefault();
    e.stopPropagation();
    // Tamanho default: primeiro com estoque (preferindo M)
    const ordered = [...product.sizes].sort((a, b) => {
      if (a.size === 'M') return -1;
      if (b.size === 'M') return 1;
      return 0;
    });
    const sz = ordered.find((s) => s.stock > 0);
    if (!sz) {
      setFeedback('Esgotado');
      setTimeout(() => setFeedback(null), 1500);
      return;
    }
    add({
      productId: product.id,
      name: product.name,
      size: sz.size,
      unitPrice: product.price,
      quantity: 1,
      imageUrl: product.imageUrl,
    });
    setFeedback(`Adicionado (${sz.size})`);
    setTimeout(() => setFeedback(null), 1500);
  }

  return (
    <button type="button" className="primary add-cart-btn" onClick={handleClick}>
      {feedback ?? '+ Adicionar ao carrinho'}
    </button>
  );
}
