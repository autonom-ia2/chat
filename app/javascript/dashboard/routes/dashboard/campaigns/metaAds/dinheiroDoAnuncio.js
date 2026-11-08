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

// "45,50", "45.50", "R$ 45" e "1.500,00". Saem só o "R$" do começo e os espaços das bordas; qualquer outro caractere
// que não seja dígito, vírgula ou ponto é recusa ("-10", "1e2", "2 5"). Com vírgula, ela é o decimal, e o ponto só
// vale como milhar em grupos de 3 dígitos ("1.500,00"; "1.5,00" e "10,5.5" são recusa). Sem vírgula, o ponto só vale
// como decimal com 1 ou 2 casas ("6.5"): "6.000" é recusa, para não virar R$ 6,00 por engano. Mais de 2 casas também:
// nunca arredonda em silêncio.
const DIGITS = '0123456789';
const CURRENCY_PREFIX = 'R$';
const MAX_DECIMALS = 2;
const THOUSANDS_GROUP = 3;

const onlyDigits = text => [...text].every(char => DIGITS.includes(char));

const withoutPrefix = text => {
  const trimmed = text.trim();
  return trimmed.startsWith(CURRENCY_PREFIX)
    ? trimmed.slice(CURRENCY_PREFIX.length).trim()
    : trimmed;
};

// "1.500" → "1500"; grupo fora do padrão (primeiro de 1 a 3 dígitos, os outros de 3) → null.
const wholeWithThousands = text => {
  const [first, ...groups] = text.split('.');
  const firstOk =
    first.length >= 1 && first.length <= THOUSANDS_GROUP && onlyDigits(first);
  const groupsOk = groups.every(
    group => group.length === THOUSANDS_GROUP && onlyDigits(group)
  );
  return firstOk && groupsOk ? [first, ...groups].join('') : null;
};

const decimalsOk = decimals =>
  decimals === undefined ||
  (decimals.length >= 1 &&
    decimals.length <= MAX_DECIMALS &&
    onlyDigits(decimals));

// { whole, decimals } com só dígitos, ou null quando o texto não é um valor sem ambiguidade.
const amountParts = text => {
  const clean = withoutPrefix(String(text ?? ''));
  if (!clean) return null;
  const comma = clean.includes(',');
  const [rawWhole, decimals, ...rest] = clean.split(comma ? ',' : '.');
  if (rest.length || !decimalsOk(decimals)) return null;
  const whole =
    comma && rawWhole.includes('.') ? wholeWithThousands(rawWhole) : rawWhole;
  if (whole === null || !onlyDigits(whole)) return null;
  if (!whole && decimals === undefined) return null;
  return { whole: whole || '0', decimals: decimals || '' };
};

export const parseAmount = text => {
  const parts = amountParts(text);
  return parts ? Number(`${parts.whole}.${parts.decimals || '0'}`) : null;
};

// Contas de dinheiro em centavos inteiros, nunca em float: "1.500,00" → 150000; "20.57" (do servidor) ou 20.57 →
// 2057. Texto que não é valor → null.
export const CENTS = 100;

export const amountCents = text => {
  const parts = amountParts(text);
  return parts
    ? Number(parts.whole) * CENTS +
        Number(parts.decimals.padEnd(MAX_DECIMALS, '0'))
    : null;
};

// Só para mostrar (money, withWords): a conta já foi feita em centavos.
export const centsToAmount = cents => cents / CENTS;

// O valor como o servidor recebe: texto decimal com 2 casas ("1500.00", "6.50"), sem passar por float.
export const decimalAmount = text => {
  const parts = amountParts(text);
  return parts
    ? `${parts.whole}.${parts.decimals.padEnd(MAX_DECIMALS, '0')}`
    : null;
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
