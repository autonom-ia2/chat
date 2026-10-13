// Convidados e caixas do formulário de reunião do Google/Microsoft. A janela
// do calendário e o card do funil (#1423) usam as mesmas regras.
const EMAIL_PATTERN = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

export const normalizeEmail = email => email.toString().trim().toLowerCase();
export const isValidEmail = email => EMAIL_PATTERN.test(normalizeEmail(email));

// As iniciais do selo: das duas primeiras palavras do nome, ou do começo do
// e-mail (antes do @, partido em ponto, hífen e sublinhado).
const SEPARADORES = ['.', '_', '-'];
export const guestInitials = guest => {
  const fonte = guest.name || String(guest.email || '').split('@')[0];
  const partes = SEPARADORES.reduce(
    (pedacos, separador) => pedacos.flatMap(parte => parte.split(separador)),
    fonte.split(' ')
  ).filter(Boolean);
  return partes
    .slice(0, 2)
    .map(parte => parte[0])
    .join('')
    .toUpperCase();
};

export const isDepartmentMailbox = inbox =>
  inbox?.shared ||
  inbox?.kind === 'department' ||
  inbox?.mailbox_type === 'department' ||
  inbox?.mailboxType === 'department';

export const normalizeProvider = provider => {
  const value = provider?.toString().toLowerCase() || '';
  return value.includes('microsoft') || value.includes('outlook')
    ? 'microsoft'
    : 'google';
};

export const mailboxLabel = (t, inbox) => {
  const S = 'CRM_KANBAN.CALENDAR.MEETING_SCHEDULER';
  const name =
    inbox?.calendar_identity ||
    inbox?.calendarIdentity ||
    inbox?.email ||
    inbox?.name ||
    t(`${S}.MAILBOX_FALLBACK`, { id: inbox?.id });
  const kind = isDepartmentMailbox(inbox)
    ? t(`${S}.MAILBOX_DEPARTMENT`)
    : t(`${S}.MAILBOX_PERSONAL`);
  return `${name} - ${kind}`;
};

export const generateIdempotencyKey = () =>
  window.crypto?.randomUUID?.() ||
  `${Date.now()}-${Math.random().toString(36).slice(2)}`;
