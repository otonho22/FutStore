import nodemailer, { type Transporter } from 'nodemailer';

// Wrapper SMTP que cacheia o transporter e é tolerante a falha: se faltar
// configuração ou o envio quebrar, loga no console e segue a vida — nunca
// derruba a transação do pedido por causa de e-mail.

let cachedTransporter: Transporter | null = null;
let cachedConfigKey: string | null = null;
let warnedMissingConfig = false;

function configKey(): string {
  return [
    process.env.MAIL_HOST,
    process.env.MAIL_PORT,
    process.env.MAIL_USER,
    process.env.MAIL_PASS,
  ].join('|');
}

function getTransporter(): Transporter | null {
  const host = process.env.MAIL_HOST;
  const port = Number(process.env.MAIL_PORT ?? 587);
  const user = process.env.MAIL_USER;
  const pass = process.env.MAIL_PASS;

  if (!host || !user || !pass) {
    if (!warnedMissingConfig) {
      console.warn('[mailer] MAIL_HOST/USER/PASS não configurados — e-mails serão ignorados.');
      warnedMissingConfig = true;
    }
    return null;
  }

  const key = configKey();
  if (cachedTransporter && cachedConfigKey === key) return cachedTransporter;

  cachedTransporter = nodemailer.createTransport({
    host,
    port,
    secure: port === 465, // 465 = SSL, 587 = STARTTLS
    auth: { user, pass },
  });
  cachedConfigKey = key;
  return cachedTransporter;
}

export interface SendMailOptions {
  to: string;
  subject: string;
  html: string;
  text?: string;
}

export async function sendMail(opts: SendMailOptions): Promise<boolean> {
  const transporter = getTransporter();
  if (!transporter) return false;

  const devOverride = process.env.MAIL_DEV_TO?.trim();
  const to = devOverride || opts.to;
  const from = process.env.MAIL_FROM ?? process.env.MAIL_USER!;

  try {
    const info = await transporter.sendMail({
      from,
      to,
      subject: devOverride ? `[DEV → ${opts.to}] ${opts.subject}` : opts.subject,
      html: opts.html,
      text: opts.text ?? opts.html.replace(/<[^>]+>/g, ' ').replace(/\s+/g, ' ').trim(),
    });
    console.log(`[mailer] ✉️  enviado para ${to}: "${opts.subject}" (${info.messageId})`);
    return true;
  } catch (e: any) {
    console.error(`[mailer] ❌ falha ao enviar para ${to}: ${e.message}`);
    return false;
  }
}

// Chame uma vez no boot pra validar credenciais sem precisar fazer um pedido real.
export async function verifyMailerConfig(): Promise<void> {
  const transporter = getTransporter();
  if (!transporter) return;
  try {
    await transporter.verify();
    console.log('[mailer] ✅ SMTP conectado.');
  } catch (e: any) {
    console.error(`[mailer] ⚠️  SMTP falhou na verificação: ${e.message}`);
  }
}
