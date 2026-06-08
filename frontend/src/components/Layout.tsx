import { Outlet } from 'react-router-dom';
import TopNav from './TopNav';

export default function Layout() {
  return (
    <div className="app-shell">
      <TopNav />
      <main className="main">
        <Outlet />
      </main>
      <footer className="site-footer">
        <div className="footer-inner">
          <div>
            <div className="footer-brand">⚽ FUTSTORE</div>
            <div className="footer-tag">A camisa do seu time. A história do seu clube.</div>
          </div>
          <div className="footer-cols">
            <div>
              <div className="footer-col-head">Loja</div>
              <a href="/catalog">Catálogo</a>
              <a href="/copa-2026">Copa 2026</a>
            </div>
            <div>
              <div className="footer-col-head">Conta</div>
              <a href="/orders">Meus pedidos</a>
              <a href="/cart">Carrinho</a>
            </div>
            <div>
              <div className="footer-col-head">Ajuda</div>
              <a href="#">FAQ</a>
              <a href="#">Trocas e devoluções</a>
            </div>
          </div>
        </div>
        <div className="footer-bottom">© 2026 FutStore · Projeto acadêmico — todos os direitos reservados</div>
      </footer>
    </div>
  );
}
