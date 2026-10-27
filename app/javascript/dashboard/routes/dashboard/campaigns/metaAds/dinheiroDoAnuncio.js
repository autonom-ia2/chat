import { intlLocale } from './metaAdsHelpers';
import { valorPorExtenso } from './valorPorExtenso';

// Anúncios da Meta (#2198): o dinheiro do anúncio do jeito que as telas de orçamento, criar e ativar mostram. Sempre
// com centavos ("R$ 25,00") e, em real, por extenso ao lado. As contas seguem a regra da Meta para orçamento por dia:
// num dia ela pode gastar até 75% a mais, e na semana nunca passa de 7 vezes o valor por dia.
export const META_DAY_FACTOR = 1.75;
export const WEEK_DAYS = 7;
export const ROLLING_DAYS = 30;
const DAY_MS = 86_400_000;

export const money = (value, currency, locale) =>
  new Intl.NumberFormat(intlLocale(locale), {
    style: 'currency',
    currency: currency || 'BRL',
  }).format(Number(value || 0));

export const withWords = (value, currency, locale) => {
  const spelled = valorPorExtenso(value, currency, locale);
  const number = money(value, currency, locale);
  return spelled ? `${number} (${spelled})` : number;
};

// "45,50", "45.50", "R$ 45" e "1.000,00": fica só com dígitos, vírgula e ponto (o símbolo da moeda e os espaços
// saem). Com vírgula, ela é o decimal e o ponto é milhar; sem vírgula, o ponto é o decimal.
const AMOUNT_CHARS = '0123456789,.';
export const parseAmount = text => {
  const clean = [...String(text ?? '')]
    .filter(char => AMOUNT_CHARS.includes(char))
    .join('');
  if (!clean) return null;
  const normalized = clean.includes(',')
    ? clean.split('.').join('').split(',').join('.')
    : clean;
  const number = Number(normalized);
  return Number.isFinite(number) ? Math.round(number * 100) / 100 : null;
};

// Dias do calendário como 'AAAA-MM-DD', no relógio de quem vê, sem fuso.
const isoOf = date => {
  const month = String(date.getMonth() + 1).padStart(2, '0');
  const day = String(date.getDate()).padStart(2, '0');
  return `${date.getFullYear()}-${month}-${day}`;
};

export const todayIso = () => isoOf(new Date());

export const addDays = (iso, days) => {
  const date = new Date(`${iso}T12:00:00`);
  date.setDate(date.getDate() + days);
  return isoOf(date);
};

// Dias de start a end, contando os dois.
export const daysBetween = (start, end) =>
  Math.round(
    (new Date(`${end}T12:00:00`) - new Date(`${start}T12:00:00`)) / DAY_MS
  ) + 1;

export const longDate = (iso, locale) =>
  iso
    ? new Date(`${iso.slice(0, 10)}T12:00:00`).toLocaleDateString(
        intlLocale(locale),
        { day: 'numeric', month: 'long', year: 'numeric' }
      )
    : null;
