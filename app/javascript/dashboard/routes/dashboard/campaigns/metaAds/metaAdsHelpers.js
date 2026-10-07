// Anúncios da Meta (#1047): formatos e códigos de erro compartilhados pelas etapas.

const RELATIVE_UNITS = [
  { unit: 'year', seconds: 365 * 24 * 60 * 60 },
  { unit: 'month', seconds: 30 * 24 * 60 * 60 },
  { unit: 'day', seconds: 24 * 60 * 60 },
  { unit: 'hour', seconds: 60 * 60 },
  { unit: 'minute', seconds: 60 },
  { unit: 'second', seconds: 1 },
];

export const intlLocale = locale => (locale || 'en').replace('_', '-');

// "há 2 horas", do próprio timestamp; null quando não há data válida.
export const relativeTime = (value, locale) => {
  const date = new Date(value || '');
  if (!value || Number.isNaN(date.getTime())) return null;

  const seconds = (date.getTime() - Date.now()) / 1000;
  const { unit, seconds: size } =
    RELATIVE_UNITS.find(item => Math.abs(seconds) >= item.seconds) ||
    RELATIVE_UNITS.at(-1);
  return new Intl.RelativeTimeFormat(intlLocale(locale), {
    numeric: 'auto',
  }).format(Math.round(seconds / size), unit);
};

// "16:52", hora local do aviso; null quando não há data válida.
export const clockTime = (value, locale) => {
  const date = new Date(value || '');
  if (!value || Number.isNaN(date.getTime())) return null;

  return date.toLocaleTimeString(intlLocale(locale), {
    hour: '2-digit',
    minute: '2-digit',
  });
};

export const money = (value, currency, locale) => {
  if (value === null || value === undefined) return null;
  return new Intl.NumberFormat(intlLocale(locale), {
    style: 'currency',
    currency: currency || 'BRL',
    maximumFractionDigits: 0,
  }).format(Number(value));
};

// Códigos que a API devolve em `error` (docs/crm/anuncios-meta-f1.md).
const ERROR_KEYS = {
  platform_unavailable: 'PLATFORM_UNAVAILABLE',
  no_portfolio: 'NO_PORTFOLIO',
  token_missing: 'TOKEN_MISSING',
  not_shared: 'NOT_SHARED',
  platform_access_pending: 'PLATFORM_ACCESS_PENDING',
  not_your_portfolio: 'NOT_YOUR_PORTFOLIO',
  ad_account_in_use: 'AD_ACCOUNT_IN_USE',
  pixel_not_found: 'PIXEL_NOT_FOUND',
  no_access: 'NO_ACCESS',
  meta_unavailable: 'META_UNAVAILABLE',
  token_invalid: 'TOKEN_INVALID',
  invalid_ad_account: 'INVALID_AD_ACCOUNT',
  not_connected: 'NOT_CONNECTED',
};

export const errorMessageKey = error => {
  const code = error?.response?.data?.error;
  return `CRM_KANBAN.META_ADS_HUB.ERRORS.${ERROR_KEYS[code] || 'GENERIC'}`;
};

// Etapa em que a conexão está: 1 conectar, 2 conta, 3 destinos, 4 vendas, 5 tudo pronto.
export const currentStep = connection => {
  if (!connection?.configured) return 1;
  if (!connection.verified_at || !connection.ad_account) return 2;
  const destinations = connection.destinations || {};
  if (!destinations.whatsapp && !destinations.site) return 3;
  if (!connection.sales_signal?.enabled) return 4;
  return 5;
};

// Dinheiro com centavos só quando há centavos ("R$ 163,51", "R$ 842"), como no painel (#1088).
export const amount = (value, currency, locale) =>
  new Intl.NumberFormat(intlLocale(locale), {
    style: 'currency',
    currency: currency || 'BRL',
    minimumFractionDigits: Number.isInteger(Number(value)) ? 0 : 2,
    maximumFractionDigits: 2,
  }).format(Number(value || 0));

// Veredito de cada anúncio (#1088): fundo claro do tom com texto escuro do mesmo tom. Os dois mudam juntos
// no tema escuro, então o contraste se mantém. Usado no cartão do painel e no anúncio por dentro.
export const VERDICT_CLASSES = {
  up: 'bg-n-teal-3 text-n-teal-11',
  keep: 'bg-n-blue-3 text-n-blue-11',
  signal: 'bg-n-amber-3 text-n-amber-11',
  review: 'bg-n-ruby-3 text-n-ruby-11',
  early: 'bg-n-alpha-2 text-n-slate-11',
};

// Sem a imagem do anúncio, cada um ganha uma cor, para não virarem cartões iguais. Cores fixas e escuras (o
// nome vai em branco por cima): as do tema clareiam no modo escuro. A cor sai do ID do anúncio, não da posição
// na lista: o cartão e o anúncio por dentro mostram a mesma cor, e ela não muda quando a ordem muda.
const THUMBS = [
  'from-[#2563EB] to-[#0D2344]',
  'from-[#B45309] to-[#78350F]',
  'from-[#0F766E] to-[#134E4A]',
  'from-[#4F46E5] to-[#312E81]',
];

export const thumbClass = adId => {
  const sum = [...String(adId ?? '')].reduce(
    (total, char) => total + char.charCodeAt(0),
    0
  );
  return THUMBS[sum % THUMBS.length];
};
