import { useEffect, useState } from 'react';
import { useNavigate, useParams } from 'react-router-dom';
import { api } from '../lib/api';
import { brl } from '../lib/format';
import { useCart } from '../context/CartContext';
import type { Product } from '../types';

export default function ProductDetail() {
  const { id } = useParams();
  const navigate = useNavigate();
  const { add } = useCart();
  const [product, setProduct] = useState<Product | null>(null);
  const [size, setSize] = useState<string>('');
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!id) return;
    api<Product>(`/api/products/${id}`).then((p) => {
      setProduct(p);
      const first = p.sizes.find((s) => s.stock > 0);
      setSize(first?.size ?? '');
    }).catch((e) => setError(e.message));
  }, [id]);

  if (error) return <div className="alert error">{error}</div>;
  if (!product) return <p className="muted">Carregando…</p>;

  const chosen = product.sizes.find((s) => s.size === size);

  function handleAdd() {
    if (!chosen || chosen.stock < 1) return;
    add({
      productId: product!.id,
      name: product!.name,
      size: chosen.size,
      unitPrice: product!.price,
      quantity: 1,
      imageUrl: product!.imageUrl,
    });
    navigate('/cart');
  }

  return (
    <div className="grid" style={{ gridTemplateColumns: 'minmax(0, 1fr) minmax(0, 1fr)', alignItems: 'start' }}>
      <div>
        <img src={product.imageUrl} alt={product.name}
          style={{ width: '100%', borderRadius: 'var(--radius)', background: 'var(--bg-elev-2)' }} />
        {product.images?.length > 0 && (
          <div className="row" style={{ marginTop: '0.5rem' }}>
            {product.images.map((url) => (
              <img key={url} src={url} alt="" style={{ width: 64, height: 64, objectFit: 'cover', borderRadius: 6 }} />
            ))}
          </div>
        )}
      </div>
      <div className="col" style={{ gap: '0.75rem' }}>
        <div className="tag">{product.category}</div>
        <h1 style={{ margin: 0 }}>{product.name}</h1>
        <div className="muted">{product.team}</div>
        <div style={{ fontSize: '1.6rem', fontWeight: 700, color: 'var(--primary)' }}>{brl(product.price)}</div>
        <p>{product.description}</p>

        <div>
          <label>Tamanho</label>
          <div className="row">
            {product.sizes.map((s) => (
              <button key={s.size}
                className={size === s.size ? 'primary' : ''}
                disabled={s.stock < 1}
                onClick={() => setSize(s.size)}>
                {s.size} {s.stock < 1 && '(esgotado)'}
              </button>
            ))}
          </div>
          {chosen && <div className="muted" style={{ marginTop: '0.5rem' }}>Estoque: {chosen.stock}</div>}
        </div>

        <div className="card" style={{ background: 'var(--bg-elev-2)', fontSize: '0.85rem' }}>
          <strong>Guia de tamanhos (referência)</strong>
          <ul style={{ margin: '0.5rem 0 0 1rem', padding: 0 }}>
            <li>P — tórax 96–100cm</li>
            <li>M — tórax 100–106cm</li>
            <li>G — tórax 106–112cm</li>
            <li>GG — tórax 112–118cm</li>
          </ul>
        </div>

        <button className="primary" disabled={!chosen || chosen.stock < 1} onClick={handleAdd}>
          Adicionar ao carrinho
        </button>
      </div>
    </div>
  );
}
