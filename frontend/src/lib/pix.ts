// Gerador de BR Code Pix estático conforme manual EMV/BCB.
// Cada campo é codificado em TLV: ID(2) + LENGTH(2) + VALUE.
// O payload termina com CRC16 CCITT-FALSE (poly 0x1021, init 0xFFFF).

export interface PixParams {
  key: string;          // chave Pix do recebedor
  name: string;         // nome do recebedor (até 25 chars)
  city: string;         // cidade do recebedor (até 15 chars)
  amount?: number;      // valor em reais (opcional — sem ele, pagador digita)
  txid?: string;        // referência (até 25 chars alfanuméricos). Default: ***
}

function tlv(id: string, value: string): string {
  const len = value.length.toString().padStart(2, '0');
  return `${id}${len}${value}`;
}

// CRC16-CCITT-FALSE: polinômio 0x1021, valor inicial 0xFFFF, sem reflexão, XOR-out 0.
function crc16(payload: string): string {
  let crc = 0xffff;
  for (let i = 0; i < payload.length; i++) {
    crc ^= payload.charCodeAt(i) << 8;
    for (let b = 0; b < 8; b++) {
      crc = (crc & 0x8000) !== 0 ? ((crc << 1) ^ 0x1021) & 0xffff : (crc << 1) & 0xffff;
    }
  }
  return crc.toString(16).toUpperCase().padStart(4, '0');
}

// Remove acentos (faixa Unicode dos combining marks U+0300..U+036F) e
// força ASCII imprimível — exigência do BR Code pra name/city.
function sanitize(s: string, max: number): string {
  return s
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .replace(/[^\x20-\x7E]/g, '')
    .trim()
    .slice(0, max)
    .toUpperCase();
}

export function buildPixPayload({ key, name, city, amount, txid = '***' }: PixParams): string {
  // 26 — Merchant Account Information (Pix)
  const merchantAccount = tlv('00', 'BR.GOV.BCB.PIX') + tlv('01', key);

  // 62 — Additional Data Field (TXID dentro do 05)
  const additional = tlv('05', txid.slice(0, 25));

  const parts = [
    tlv('00', '01'),                              // Payload Format Indicator
    tlv('26', merchantAccount),                   // Merchant Account Info
    tlv('52', '0000'),                            // Merchant Category Code
    tlv('53', '986'),                             // Currency: BRL
    ...(amount != null ? [tlv('54', amount.toFixed(2))] : []),
    tlv('58', 'BR'),                              // Country
    tlv('59', sanitize(name, 25)),                // Merchant Name
    tlv('60', sanitize(city, 15)),                // Merchant City
    tlv('62', additional),                        // Additional Data
  ];

  // CRC é calculado sobre o payload completo + o cabeçalho do campo 63 ("6304")
  const partial = parts.join('') + '6304';
  return partial + crc16(partial);
}
