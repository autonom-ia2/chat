export const unwrapCollection = payload => {
  if (Array.isArray(payload)) return payload;
  if (Array.isArray(payload?.data)) return payload.data;
  if (Array.isArray(payload?.items)) return payload.items;
  if (Array.isArray(payload?.invoices)) return payload.invoices;
  if (Array.isArray(payload?.payments)) return payload.payments;
  return [];
};

export const extractErrorMessage = error => {
  const payload = error?.response?.data;
  if (typeof payload?.error === 'string') return payload.error;
  if (typeof payload?.error?.message === 'string') return payload.error.message;
  if (typeof payload?.message === 'string') return payload.message;
  return null;
};

export const formatMoney = (value, currency = 'BRL', locale = 'pt-BR') => {
  const amount = Number(value || 0);
  return new Intl.NumberFormat(locale, {
    style: 'currency',
    currency: currency || 'BRL',
  }).format(amount);
};

export const formatDate = (value, locale = 'pt-BR') => {
  if (!value) return '-';
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return '-';
  return new Intl.DateTimeFormat(locale, {
    dateStyle: 'short',
    timeZone: 'UTC',
  }).format(date);
};

// Unknown statuses from the gateway are shown as they come.
const statusLabel = (scope, statuses) => (t, status) =>
  statuses.includes(status)
    ? t(`FINANCIAL.${scope}.${status.toUpperCase()}`)
    : status || '-';

export const subscriptionStatusLabel = statusLabel('SUBSCRIPTION_STATUS', [
  'active',
  'canceled',
  'past_due',
  'trialing',
  'unpaid',
]);
export const invoiceStatusLabel = statusLabel('INVOICE_STATUS', [
  'pending',
  'paid',
  'canceled',
  'overdue',
  'refunded',
]);
export const paymentStatusLabel = statusLabel('PAYMENT_STATUS', [
  'pending',
  'paid',
  'failed',
  'refunded',
  'canceled',
]);

export const statusToneClass = status => {
  if (['paid', 'active'].includes(status)) {
    return 'bg-green-100 text-green-800 dark:bg-green-900/30 dark:text-green-200';
  }
  if (['pending', 'trialing'].includes(status)) {
    return 'bg-yellow-100 text-yellow-800 dark:bg-yellow-900/30 dark:text-yellow-200';
  }
  if (
    ['overdue', 'past_due', 'failed', 'unpaid', 'canceled'].includes(status)
  ) {
    return 'bg-red-100 text-red-800 dark:bg-red-900/30 dark:text-red-200';
  }
  return 'bg-n-alpha-2 text-n-slate-11';
};
