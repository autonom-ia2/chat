import { intlLocale } from './metaAdsHelpers';
import { valorPorExtenso } from './valorPorExtenso';

// Anúncios da Meta (#2198): o dinheiro do anúncio do jeito que as telas de orçamento, criar e ativar mostram. Sempre
// com centavos ("R$ 25,00") e, em real, por extenso ao lado. As contas seguem a regra da Meta para orçamento por dia:
// num dia ela pode gastar até 75% a mais, e na semana nunca passa de 7 vezes o valor por dia.
export const META_DAY_FACTOR = 1.75;
export const WEEK_DAYS = 7;
export const ROLLING_DAYS = 30;
const DAY_MS = 86_400_000;

// Sem moeda confirmada pelo servidor, não formata: nunca presume real.
export const money = (value, currency, locale) =>
  currency
    ? new Intl.NumberFormat(intlLocale(locale), {
        style: 'currency',
        currency,
      }).format(Number(value || 0))
    : '';

export const withWords = (value, currency, locale) => {
  if (!currency) return '';
  const spelled = valorPorExtenso(value, currency, locale);
  const number = money(value, currency, locale);
  return spelled ? `${number} (${spelled})` : number;
};

// "45,50", "45.50", "R$ 45" e "1.000,00": o "R$" do começo e os espaços saem; qualquer outro caractere que não seja
// dígito, vírgula ou ponto é recusa ("-10" e "1e2" não viram 10 nem 12). Com vírgula, ela é o decimal e o ponto é
// milhar. Sem vírgula, o ponto só vale como decimal com 1 ou 2 casas ("6.5", "6.50"): "6.000" e "1.000.000" são
// recusados, para não virarem R$ 6,00 por engano. Mais de 2 casas também é recusa: nunca arredonda em silêncio.
const AMOUNT_CHARS = '0123456789,.';
const CURRENCY_PREFIX = 'R$';
const MAX_DECIMALS = 2;
const withoutPrefix = text =>
  text.startsWith(CURRENCY_PREFIX) ? text.slice(CURRENCY_PREFIX.length) : text;
export const parseAmount = text => {
  const clean = [...withoutPrefix(String(text ?? '').trim())]
    .filter(char => char.trim() !== '')
    .join('');
  if (!clean) return null;
  if (![...clean].every(char => AMOUNT_CHARS.includes(char))) return null;
  const comma = clean.includes(',');
  const separator = comma ? ',' : '.';
  const digits = comma ? clean.split('.').join('') : clean;
  const [whole, decimals, ...rest] = digits.split(separator);
  if (rest.length) return null;
  if (decimals !== undefined) {
    if (!decimals.length || decimals.length > MAX_DECIMALS) return null;
  }
  const number = Number(`${whole || '0'}.${decimals || '0'}`);
  return Number.isFinite(number) ? number : null;
};

// Dias do calendário como 'AAAA-MM-DD', no relógio de quem vê, sem fuso.
const isoOf = date => {
  const month = String(date.getMonth() + 1).padStart(2, '0');
  const day = String(date.getDate()).padStart(2, '0');
  return `${date.getFullYear()}-${month}-${day}`;
};

// Hoje no relógio de quem vê. Para as datas do anúncio, vale o dia que o servidor manda no fuso da conta de anúncios
// (`today` das opções de criar e do orçamento); este é só o recurso de quem ainda não recebeu.
export const todayIso = () => isoOf(new Date());

export const todayOfAccount = serverToday => serverToday || todayIso();

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
