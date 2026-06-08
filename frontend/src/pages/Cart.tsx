import { Link, useNavigate } from 'react-router-dom';
import { useCart } from '../context/CartContext';
import { brl } from '../lib/format';
import JerseyImage from '../components/JerseyImage';

export default function Cart() {
  const { items, remove, setQuantity, subtotal } = useCart();
  const navigate = useNavigate();

  if (items.length === 0) {
    return (
      <div>
        <h1 className="page-title">Carrinho</h1>
        <div className="card">
          <p>Seu carrinho está vazio. <Link to="/catalog">Explore o catálogo</Link>.</p>
        </div>
      </div>
    );
  }

  return (
    <div>
      <h1 className="page-title">Carrinho</h1>
      <div className="card">
        <table>
          <thead>
            <tr>
              <th>Produto</th>
              <th>Tamanho</th>
              <th className="right">Preço</th>
              <th>Qtd</th>
              <th className="right">Subtotal</th>
              <th />
            </tr>
          </thead>
          <tbody>
            {items.map((i) => (
              <tr key={`${i.productId}-${i.size}`}>
                <td>
                  <div className="row" style={{ gap: '0.75rem' }}>
                    <JerseyImage imageUrl={i.imageUrl} name={i.name} size={48} />
                    <span>{i.name}</span>
                  </div>
                </td>
                <td>{i.size}</td>
                <td className="right">{brl(i.unitPrice)}</td>
                <td>
                  <input type="number" min={1} value={i.quantity} style={{ width: 70 }}
                    onChange={(e) => setQuantity(i.productId, i.size, parseInt(e.target.value, 10) || 1)} />
                </td>
                <td className="right">{brl(i.unitPrice * i.quantity)}</td>
                <td>
                  <button className="danger" onClick={() => remove(i.productId, i.size)}>Remover</button>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
        <div className="row" style={{ justifyContent: 'flex-end', marginTop: '1rem' }}>
          <div className="col" style={{ minWidth: 240 }}>
            <div className="row" style={{ justifyContent: 'space-between' }}>
              <span className="muted">Subtotal</span>
              <strong>{brl(subtotal)}</strong>
            </div>
            <button className="primary" onClick={() => navigate('/checkout')}>
              Ir para o checkout
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}
