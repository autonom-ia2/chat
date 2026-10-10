// Painel de resultados do agendamento (#1194): constantes e formatação sem estado.

export const PERIODS = [7, 30];
export const DEFAULT_PERIOD = 30;

// Ordem dos cinco cartões (J7-A1).
export const NUMBER_KEYS = ['sent', 'opened', 'booked', 'attended', 'no_show'];

const NUMBER_I18N = {
  sent: 'SENT',
  opened: 'OPENED',
  booked: 'BOOKED',
  attended: 'ATTENDED',
  no_show: 'NO_SHOW',
};

export const numberLabelKey = key =>
  `BOOKING.RESULTS.NUMBERS.${NUMBER_I18N[key]}.LABEL`;
export const numberHintKey = key =>
  `BOOKING.RESULTS.NUMBERS.${NUMBER_I18N[key]}.HINT`;

const NUMBER_TONES = {
  attended: 'text-n-teal-11',
  no_show: 'text-n-ruby-11',
};
export const numberToneClass = key => NUMBER_TONES[key] || 'text-n-slate-12';

const ORIGIN_I18N = {
  conversation: 'CONVERSATION',
  public_link: 'PUBLIC_LINK',
  contact_request: 'CONTACT_REQUEST',
  ai: 'AI',
};
export const originLabelKey = key =>
  `BOOKING.RESULTS.ORIGINS.${ORIGIN_I18N[key] || 'CONVERSATION'}`;

// Nada aconteceu no período: nenhum dos cinco números passou de zero.
export const isEmptyTotals = totals =>
  !totals || NUMBER_KEYS.every(key => !totals[key]);

// Largura da barra de origem em doze partes, só com classes do Tailwind (sem estilo inline).
const WIDTHS = [
  'w-0',
  'w-1/12',
  'w-2/12',
  'w-3/12',
  'w-4/12',
  'w-5/12',
  'w-6/12',
  'w-7/12',
  'w-8/12',
  'w-9/12',
  'w-10/12',
  'w-11/12',
  'w-full',
];
export const barWidthClass = (count, max) => {
  if (!count || !max) return WIDTHS[0];
  return WIDTHS[Math.max(1, Math.round((count / max) * 12))];
};

const UNITS = [
  ['day', 86400],
  ['hour', 3600],
  ['minute', 60],
];

// "há 2 dias", "há 3 horas", "agora".
export const timeAgo = (iso, locale, now = Date.now()) => {
  const date = new Date(iso);
  if (!iso || Number.isNaN(date.getTime())) return '';
  const seconds = Math.max(0, Math.round((now - date.getTime()) / 1000));
  const format = new Intl.RelativeTimeFormat(String(locale).replace('_', '-'), {
    numeric: 'auto',
  });
  const unit = UNITS.find(([, size]) => seconds >= size);
  if (!unit) return format.format(0, 'second');
  const [name, size] = unit;
  return format.format(-Math.floor(seconds / size), name);
};
