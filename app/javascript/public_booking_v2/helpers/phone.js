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
