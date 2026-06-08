import { jsPDF } from 'jspdf';
import type { Order } from '../types';
import { brl, formatDate } from './format';

const paymentLabel = (m?: string) =>
  m === 'pix' ? 'PIX' : m === 'boleto' ? 'Boleto bancário' : 'Cartão de crédito';

export function downloadNfPdf(order: Order) {
  const doc = new jsPDF({ unit: 'pt', format: 'a4' });
  const W = doc.internal.pageSize.getWidth();
  const M = 40;
  let y = M;

  doc.setFont('helvetica', 'bold');
  doc.setFontSize(18);
  doc.text('FutStore — Nota Fiscal (simulada)', M, y);
  y += 22;

  doc.setFont('helvetica', 'normal');
  doc.setFontSize(10);
  doc.setTextColor(120);
  doc.text('Documento sem valor fiscal — gerado localmente para demonstração.', M, y);
  doc.setTextColor(0);
  y += 22;

  doc.setFontSize(11);
  doc.text(`NF nº (simulado): ${order.id}`, M, y); y += 14;
  doc.text(`Emitida em: ${formatDate(order.createdAt) || new Date().toLocaleDateString('pt-BR')}`, M, y); y += 14;
  doc.text(`Forma de pagamento: ${paymentLabel(order.payment?.method)}`, M, y); y += 18;

  doc.setFont('helvetica', 'bold');
  doc.text('Destinatário', M, y); y += 14;
  doc.setFont('helvetica', 'normal');
  doc.text(order.address.fullName, M, y); y += 12;
  doc.text(
    `${order.address.street}, ${order.address.number}${order.address.complement ? ' — ' + order.address.complement : ''}`,
    M, y,
  ); y += 12;
  doc.text(`${order.address.city} / ${order.address.state} — CEP ${order.address.zip}`, M, y); y += 22;

  doc.setFont('helvetica', 'bold');
  doc.text('Itens', M, y); y += 14;
  doc.setFontSize(10);
  doc.text('Produto', M, y);
  doc.text('Tam.', M + 290, y);
  doc.text('Qtd', M + 340, y);
  doc.text('Unit.', M + 390, y);
  doc.text('Subtotal', W - M - 60, y, { align: 'left' });
  y += 4;
  doc.setLineWidth(0.5);
  doc.line(M, y, W - M, y);
  y += 12;
  doc.setFont('helvetica', 'normal');

  for (const i of order.items) {
    if (y > 760) { doc.addPage(); y = M; }
    const name = i.name.length > 48 ? i.name.slice(0, 45) + '…' : i.name;
    doc.text(name, M, y);
    doc.text(i.size, M + 290, y);
    doc.text(String(i.quantity), M + 340, y);
    doc.text(brl(i.unitPrice), M + 390, y);
    doc.text(brl(i.unitPrice * i.quantity), W - M - 60, y);
    y += 14;
  }

  y += 8;
  doc.setLineWidth(0.5);
  doc.line(M, y, W - M, y);
  y += 18;

  const right = W - M;
  const labelX = right - 180;
  doc.text('Subtotal', labelX, y); doc.text(brl(order.subtotal), right, y, { align: 'right' }); y += 14;
  doc.text('Desconto', labelX, y); doc.text(`- ${brl(order.discount)}`, right, y, { align: 'right' }); y += 14;
  doc.text('Frete', labelX, y); doc.text(brl(order.shipping), right, y, { align: 'right' }); y += 16;
  doc.setFont('helvetica', 'bold'); doc.setFontSize(12);
  doc.text('Total', labelX, y); doc.text(brl(order.total), right, y, { align: 'right' });

  doc.save(`nota-fiscal-${order.id}.pdf`);
}
