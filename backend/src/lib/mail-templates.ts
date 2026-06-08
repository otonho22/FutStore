// Templates HTML dos e-mails transacionais. Estilo inline porque clientes
// de e-mail (Gmail, Outlook) ignoram CSS externo / classes / variáveis.

export interface OrderEmailData {
  id: string;
  customerName: string;
  items: { name: string; size: string; quantity: number; unitPrice: number }[];
  total: number;
  trackingCode?: string | null;
  city?: string;
  state?: string;
}

const COLORS = {
  bg: '#0f1115',
  card: '#171a21',
  border: '#2a2f3a',
  text: '#f5f7fa',
  muted: '#8b919c',
  primary: '#22c55e',
  accent: '#fbbf24',
};

function brl(value: number): string {
  return value.toLocaleString('pt-BR', { style: 'currency', currency: 'BRL' });
}

function shortId(id: string): string {
  return id.slice(0, 8).toUpperCase();
}

function layout(opts: {
  title: string;
  preheader: string;
  intro: string;
  body: string;
  ctaText?: string;
  ctaUrl?: string;
}): string {
  return `<!doctype html>
<html lang="pt-br">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>${escapeHtml(opts.title)}</title>
</head>
<body style="margin:0;padding:0;background:${COLORS.bg};font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;color:${COLORS.text};">
  <span style="display:none;visibility:hidden;opacity:0;color:transparent;height:0;width:0;">${escapeHtml(opts.preheader)}</span>
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:${COLORS.bg};padding:32px 16px;">
    <tr><td align="center">
      <table role="presentation" width="560" cellpadding="0" cellspacing="0" style="max-width:560px;width:100%;background:${COLORS.card};border:1px solid ${COLORS.border};border-radius:16px;overflow:hidden;">
        <tr><td style="padding:24px 32px;border-bottom:1px solid ${COLORS.border};">
          <div style="font-size:22px;font-weight:900;letter-spacing:1px;">
            <span style="color:${COLORS.accent};">⚽</span>
            <span style="color:${COLORS.text};">FUTSTORE</span>
          </div>
        </td></tr>
        <tr><td style="padding:32px;">
          <h1 style="margin:0 0 12px 0;font-size:24px;color:${COLORS.text};">${escapeHtml(opts.title)}</h1>
          <p style="margin:0 0 24px 0;color:${COLORS.muted};line-height:1.5;font-size:15px;">${opts.intro}</p>
          ${opts.body}
          ${opts.ctaText && opts.ctaUrl ? `
            <div style="margin:28px 0 8px 0;text-align:center;">
              <a href="${escapeAttr(opts.ctaUrl)}" style="display:inline-block;background:${COLORS.primary};color:#06140b;text-decoration:none;font-weight:800;padding:12px 24px;border-radius:999px;font-size:15px;">
                ${escapeHtml(opts.ctaText)}
              </a>
            </div>` : ''}
        </td></tr>
        <tr><td style="padding:20px 32px;border-top:1px solid ${COLORS.border};color:${COLORS.muted};font-size:12px;text-align:center;">
          FutStore · Projeto acadêmico — © 2026<br />
          Recebeu este e-mail por engano? Pode ignorar — não responda.
        </td></tr>
      </table>
    </td></tr>
  </table>
</body>
</html>`;
}

function itemsTable(items: OrderEmailData['items'], total: number): string {
  const rows = items
    .map(
      (i) => `
      <tr>
        <td style="padding:10px 0;border-bottom:1px solid ${COLORS.border};color:${COLORS.text};font-size:14px;">
          ${escapeHtml(i.name)}<br/>
          <span style="color:${COLORS.muted};font-size:12px;">Tamanho ${escapeHtml(i.size)} · ×${i.quantity}</span>
        </td>
        <td style="padding:10px 0;border-bottom:1px solid ${COLORS.border};color:${COLORS.text};font-size:14px;text-align:right;">
          ${brl(i.unitPrice * i.quantity)}
        </td>
      </tr>`,
    )
    .join('');

  return `
    <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="margin:8px 0 16px 0;">
      ${rows}
      <tr>
        <td style="padding:14px 0 0 0;color:${COLORS.text};font-size:15px;font-weight:700;">Total</td>
        <td style="padding:14px 0 0 0;color:${COLORS.primary};font-size:18px;font-weight:800;text-align:right;">${brl(total)}</td>
      </tr>
    </table>`;
}

export function orderConfirmationEmail(d: OrderEmailData, appUrl: string): { subject: string; html: string } {
  const subject = `🧾 Pedido #${shortId(d.id)} recebido — FutStore`;
  const html = layout({
    title: 'Recebemos seu pedido!',
    preheader: `Pedido #${shortId(d.id)} confirmado. Total ${brl(d.total)}.`,
    intro: `Oi <strong style="color:${COLORS.text};">${escapeHtml(d.customerName)}</strong>, recebemos seu pedido <strong style="color:${COLORS.text};">#${shortId(d.id)}</strong> e já estamos preparando tudo. Você vai receber um novo e-mail assim que o pagamento for confirmado.`,
    body: `
      <h2 style="margin:0 0 4px 0;font-size:15px;color:${COLORS.text};">Itens do pedido</h2>
      ${itemsTable(d.items, d.total)}`,
    ctaText: 'Acompanhar pedido',
    ctaUrl: `${appUrl}/track/${encodeURIComponent(d.id)}`,
  });
  return { subject, html };
}

export function orderPaidEmail(d: OrderEmailData, appUrl: string): { subject: string; html: string } {
  const subject = `💳 Pagamento confirmado — pedido #${shortId(d.id)}`;
  const html = layout({
    title: 'Pagamento confirmado ✅',
    preheader: `Recebemos o pagamento do pedido #${shortId(d.id)}.`,
    intro: `Boa, <strong style="color:${COLORS.text};">${escapeHtml(d.customerName)}</strong>! O pagamento do seu pedido <strong style="color:${COLORS.text};">#${shortId(d.id)}</strong> foi confirmado. Agora é com a gente: começamos a separação e logo logo despachamos.`,
    body: `
      <div style="background:rgba(34,197,94,0.08);border:1px solid ${COLORS.primary};border-radius:10px;padding:14px;color:${COLORS.text};font-size:14px;">
        Próximo passo: assim que seu pedido for despachado, você recebe um e-mail com o <strong>código de rastreio</strong>.
      </div>`,
    ctaText: 'Acompanhar pedido',
    ctaUrl: `${appUrl}/track/${encodeURIComponent(d.id)}`,
  });
  return { subject, html };
}

export function orderShippedEmail(d: OrderEmailData, appUrl: string): { subject: string; html: string } {
  const code = d.trackingCode ?? '';
  const subject = `🚚 Seu pedido #${shortId(d.id)} saiu pra entrega!`;
  const trackingBlock = code
    ? `
      <div style="background:rgba(56,189,248,0.08);border:1px solid #38bdf8;border-radius:10px;padding:16px;margin:8px 0;">
        <div style="color:${COLORS.muted};font-size:12px;text-transform:uppercase;letter-spacing:1px;margin-bottom:4px;">Código de rastreio</div>
        <div style="color:${COLORS.text};font-size:18px;font-weight:800;font-family:monospace;letter-spacing:1px;">${escapeHtml(code)}</div>
        <a href="https://rastreamento.correios.com.br/app/index.php?objetos=${encodeURIComponent(code)}" style="color:#38bdf8;font-size:13px;text-decoration:none;">Ver no site dos Correios ↗</a>
      </div>`
    : '';
  const destinoBlock = d.city && d.state
    ? `<p style="margin:0 0 12px 0;color:${COLORS.muted};font-size:14px;">Destino: <strong style="color:${COLORS.text};">${escapeHtml(d.city)} / ${escapeHtml(d.state)}</strong></p>`
    : '';
  const html = layout({
    title: 'Seu pedido tá a caminho 🚚',
    preheader: code ? `Código de rastreio: ${code}` : 'Pedido despachado.',
    intro: `<strong style="color:${COLORS.text};">${escapeHtml(d.customerName)}</strong>, despachamos seu pedido <strong style="color:${COLORS.text};">#${shortId(d.id)}</strong>! Use o código abaixo pra acompanhar a entrega.`,
    body: `${trackingBlock}${destinoBlock}`,
    ctaText: 'Acompanhar em tempo real',
    ctaUrl: `${appUrl}/track/${encodeURIComponent(code || d.id)}`,
  });
  return { subject, html };
}

export function orderDeliveredEmail(d: OrderEmailData, appUrl: string): { subject: string; html: string } {
  const subject = `📦 Pedido #${shortId(d.id)} entregue!`;
  const html = layout({
    title: 'Chegou! 📦',
    preheader: 'Seu pedido foi entregue.',
    intro: `<strong style="color:${COLORS.text};">${escapeHtml(d.customerName)}</strong>, seu pedido <strong style="color:${COLORS.text};">#${shortId(d.id)}</strong> foi entregue. Esperamos que você arrase com a camisa nova!`,
    body: `
      <div style="background:rgba(251,191,36,0.08);border:1px solid ${COLORS.accent};border-radius:10px;padding:14px;color:${COLORS.text};font-size:14px;">
        💛 <strong>Curtiu a experiência?</strong> Volta no catálogo, tem mais peças esperando você.
      </div>`,
    ctaText: 'Voltar pra loja',
    ctaUrl: appUrl,
  });
  return { subject, html };
}

// === Helpers ===
function escapeHtml(s: string): string {
  return String(s)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

function escapeAttr(s: string): string {
  return escapeHtml(s);
}
