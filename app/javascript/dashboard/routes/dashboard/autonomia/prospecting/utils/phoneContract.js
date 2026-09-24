// Contrato único de telefone da prospecção (#677), espelho de
// Autonomia::Prospecting::PhoneContract no backend. Os dois rodam a tabela
// spec/fixtures/prospecting_phone_contract_cases.json.
//
// Regra: número com + é lido como internacional. Sem +, primeiro como número
// nacional da região da busca (assim "(55) 99988-7766" é DDD 55, não o DDI do
// Brasil); se não for válido lá, como internacional sem o +. Número que não
// valida em nenhum dos dois não tem telefone.
//
// Usa os metadados completos (max), como a gem do backend: com os mínimos a
// validação olha só o tamanho e aceita números que o backend recusa.
import {
  isSupportedCountry,
  parsePhoneNumberFromString,
} from 'libphonenumber-js/max';

export const DEFAULT_PHONE_REGION = 'BR';

const normalizeRegion = region => {
  const code = String(region || '')
    .trim()
    .toUpperCase();
  return isSupportedCountry(code) ? code : DEFAULT_PHONE_REGION;
};

const onlyDigits = text =>
  Array.from(text)
    .filter(char => char >= '0' && char <= '9')
    .join('');

const candidates = (text, region) => {
  if (text.startsWith('+')) return [[text, undefined]];

  const digits = onlyDigits(text);
  if (!digits) return [];

  return [
    [text, region],
    [`+${digits}`, undefined],
  ];
};

export const parsePhone = (raw, region = DEFAULT_PHONE_REGION) => {
  const text = String(raw ?? '').trim();
  if (!text) return null;

  const match = candidates(text, normalizeRegion(region))
    .map(([candidate, country]) =>
      parsePhoneNumberFromString(candidate, country)
    )
    .find(parsed => parsed?.isValid());
  if (!match) return null;

  return {
    e164: match.number,
    digits: match.number.slice(1),
    country: match.country,
  };
};

export const phoneE164 = (raw, region = DEFAULT_PHONE_REGION) =>
  parsePhone(raw, region)?.e164 || '';

// Região da busca: settings.search_country (ISO 3166 alfa-2), com BR como padrão.
export const phoneRegionFromSettings = settings =>
  normalizeRegion(settings?.search_country);
