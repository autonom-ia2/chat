// Telefone digitado pela pessoa: guardamos só os dígitos e mostramos formatado. Sem regex: métodos de string.
// A validação de verdade (E.164) é do servidor, com a biblioteca de telefone do sistema (J2-A3).
export const DEFAULT_COUNTRY_CODE = '55';
const DIGITS = '0123456789';
const BR_MAX_DIGITS = 11;
const BR_MIN_DIGITS = 10;
const OTHER_MIN_DIGITS = 6;
const MAX_DIGITS = 15;

export const onlyDigits = value =>
  [...String(value ?? '')].filter(char => DIGITS.includes(char)).join('');

const formatBrazil = digits => {
  const national = digits.slice(0, BR_MAX_DIGITS);
  if (!national) return '';
  if (national.length <= 2) return `(${national}`;

  const area = national.slice(0, 2);
  const rest = national.slice(2);
  if (rest.length <= 4) return `(${area}) ${rest}`;

  const split = rest.length > 8 ? 5 : 4;
  return `(${area}) ${rest.slice(0, split)}-${rest.slice(split)}`;
};

export const formatNational = (digits, countryCode) =>
  countryCode === DEFAULT_COUNTRY_CODE
    ? formatBrazil(digits)
    : digits.slice(0, MAX_DIGITS);

const maxNationalDigits = countryCode =>
  countryCode === DEFAULT_COUNTRY_CODE ? BR_MAX_DIGITS : MAX_DIGITS;

// O que a pessoa digitou ou colou, reduzido ao número nacional que vai para o servidor (o mesmo que aparece na tela).
// Colado com o código do país ("+55 11 98765-4321", "0055...", "5511987654321"), o código sai; no Brasil, o zero da
// operadora antes do DDD ("011...") também sai.
export const normalizeNational = (
  raw,
  countryCode,
  { pasted = false } = {}
) => {
  const text = String(raw ?? '').trim();
  const country = onlyDigits(countryCode);
  let digits = onlyDigits(text);
  const hasPlus = text.startsWith('+');
  if (text.startsWith('00')) digits = digits.slice(2);
  const tooLong = digits.length > maxNationalDigits(country);
  if (country && digits.startsWith(country) && (hasPlus || pasted || tooLong)) {
    digits = digits.slice(country.length);
  }
  if (country === DEFAULT_COUNTRY_CODE && digits.startsWith('0')) {
    digits = digits.slice(1);
  }
  return digits.slice(0, maxNationalDigits(country));
};

// Posição do cursor logo depois do n-ésimo dígito do texto formatado: editar no meio não joga o cursor para o fim.
export const caretAfterDigits = (formatted, digitCount) => {
  if (digitCount <= 0) return 0;
  let seen = 0;
  const index = [...formatted].findIndex(char => {
    if (DIGITS.includes(char)) seen += 1;
    return seen === digitCount;
  });
  return index === -1 ? formatted.length : index + 1;
};

export const isPlausiblePhone = (countryCode, national) => {
  const country = onlyDigits(countryCode);
  const digits = onlyDigits(national);
  if (!country) return false;
  if (country === DEFAULT_COUNTRY_CODE) {
    return digits.length >= BR_MIN_DIGITS && digits.length <= BR_MAX_DIGITS;
  }
  return digits.length >= OTHER_MIN_DIGITS && digits.length <= MAX_DIGITS;
};

export const toInternational = (countryCode, national) =>
  `+${onlyDigits(countryCode)}${onlyDigits(national)}`;

// Conferência leve só para avisar cedo; quem decide é o servidor.
export const looksLikeEmail = value => {
  const email = String(value ?? '').trim();
  const at = email.indexOf('@');
  return (
    at > 0 &&
    at === email.lastIndexOf('@') &&
    !email.includes(' ') &&
    email.slice(at + 1).includes('.') &&
    !email.endsWith('.')
  );
};
