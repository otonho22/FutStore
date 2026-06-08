import { useEffect, useState } from 'react';
import { useNavigate, useParams } from 'react-router-dom';
import { api } from '../lib/api';
import { brl } from '../lib/format';
import { useCart } from '../context/CartContext';
import JerseyImage from '../components/JerseyImage';
import type { Product } from '../types';

export default function ProductDetail() {
  const { id } = useParams();
  const navigate = useNavigate();
  const { add } = useCart();
  const [product, setProduct] = useState<Product | null>(null);
  const [size, setSize] = useState<string>('');
  const [error, setError] = useState<string | null>(null);
  const [activeImg, setActiveImg] = useState<string>('');
  const [zoomOpen, setZoomOpen] = useState(false);

  useEffect(() => {
    if (!id) return;
    api<Product>(`/api/products/${id}`).then((p) => {
      setProduct(p);
      setActiveImg(p.imageUrl);
      const first = p.sizes.find((s) => s.stock > 0);
      setSize(first?.size ?? '');
    }).catch((e) => setError(e.message));
  }, [id]);

  useEffect(() => {
    if (!zoomOpen) return;
    const onKey = (e: KeyboardEvent) => { if (e.key === 'Escape') setZoomOpen(false); };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [zoomOpen]);

  if (error) return <div className="alert error">{error}</div>;
  if (!product) return <p className="muted">Carregando…</p>;

  const chosen = product.sizes.find((s) => s.size === size);
  const gallery = [product.imageUrl, ...(product.images ?? [])].filter((u, i, arr) => u && arr.indexOf(u) === i);

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
        <div
          onClick={() => setZoomOpen(true)}
          title="Clique para ampliar"
          style={{ cursor: 'zoom-in' }}
        >
          <JerseyImage imageUrl={activeImg || product.imageUrl} team={product.team} name={product.name} alt={product.name}
            style={{ width: '100%', borderRadius: 'var(--radius)', background: 'var(--bg-elev-2)' }} />
        </div>
        {gallery.length > 1 && (
          <div className="row" style={{ marginTop: '0.5rem', flexWrap: 'wrap' }}>
            {gallery.map((url) => {
              const isActive = (activeImg || product.imageUrl) === url;
              return (
                <button
                  key={url}
                  onClick={() => setActiveImg(url)}
                  title="Trocar imagem"
                  style={{
                    padding: 0, border: isActive ? '2px solid var(--primary)' : '2px solid transparent',
                    borderRadius: 8, background: 'transparent', cursor: 'pointer',
                  }}
                >
                  <JerseyImage imageUrl={url} team={product.team} name={product.name} size={64} />
                </button>
              );
            })}
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

      {zoomOpen && (
        <div
          onClick={() => setZoomOpen(false)}
          role="dialog"
          aria-label="Imagem ampliada"
          style={{
            position: 'fixed', inset: 0, background: 'rgba(0,0,0,0.85)',
            display: 'flex', alignItems: 'center', justifyContent: 'center',
            zIndex: 1000, cursor: 'zoom-out', padding: '2rem',
          }}
        >
          <div style={{ maxWidth: '90vw', maxHeight: '90vh', width: 'min(720px, 90vw)' }} onClick={(e) => e.stopPropagation()}>
            <JerseyImage imageUrl={activeImg || product.imageUrl} team={product.team} name={product.name} alt={product.name}
              style={{ width: '100%', borderRadius: 'var(--radius)' }} />
          </div>
          <button
            onClick={() => setZoomOpen(false)}
            aria-label="Fechar"
            style={{
              position: 'absolute', top: 16, right: 16,
              background: 'rgba(255,255,255,0.1)', color: '#fff', border: 'none',
              borderRadius: 999, width: 40, height: 40, fontSize: 20, cursor: 'pointer',
            }}
          >×</button>
        </div>
      )}
    </div>
  );
}
