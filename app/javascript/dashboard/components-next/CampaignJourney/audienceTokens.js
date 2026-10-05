// WhatsApp API message tokens of the journey (#993 front of #999, api-999.md §2.2): contact
// tokens and one {{publico.<key>}} per extra column of the audience. The key is the header
// normalized like CampaignImports::HeaderMapper.normalize_key on the server (no accents,
// lower case, spaces and hyphens become "_", only a-z 0-9 _; a repeated key gets "_2"), done
// character by character, no regular expressions.
export const CONTACT_TOKENS = [
  { token: 'contact.first_name', labelKey: 'FIRST_NAME' },
  { token: 'contact.name', labelKey: 'NAME' },
  { token: 'contact.company', labelKey: 'COMPANY' },
];

export const AUDIENCE_PREFIX = 'publico.';

const isCombiningMark = char => {
  const code = char.charCodeAt(0);
  return code >= 0x300 && code <= 0x36f;
};
const isSeparator = char => char === '-' || char.trim() === '';
const isKeyChar = char =>
  (char >= 'a' && char <= 'z') || (char >= '0' && char <= '9') || char === '_';

export const normalizeKey = header => {
  const plain = String(header || '')
    .trim()
    .normalize('NFD')
    .split('')
    .filter(char => !isCombiningMark(char))
    .join('')
    .toLowerCase();
  let key = '';
  let inSeparator = false;
  plain.split('').forEach(char => {
    if (isSeparator(char)) {
      if (!inSeparator) key += '_';
      inSeparator = true;
      return;
    }
    inSeparator = false;
    if (isKeyChar(char)) key += char;
  });
  return key;
};

/** [{ key: 'vencimento', header: 'Vencimento', token: 'publico.vencimento' }] */
export const audienceColumnTokens = extraColumns => {
  const taken = new Set();
  return (extraColumns || []).flatMap(header => {
    let key = normalizeKey(header);
    if (!key) return [];
    while (taken.has(key)) key = `${key}_2`;
    taken.add(key);
    return [{ key, header: String(header), token: `${AUDIENCE_PREFIX}${key}` }];
  });
};

/** Inserts `{{token}}` at the cursor position of a text (or at the end). */
export const insertToken = (text, token, position = text.length) => {
  const at = Math.min(Math.max(position, 0), text.length);
  return `${text.slice(0, at)}{{${token}}}${text.slice(at)}`;
};

const contactValue = (token, sample) => {
  const name = String(sample?.name || '').trim();
  if (token === 'contact.first_name')
    return sample?.first_name || name.split(' ')[0] || '';
  if (token === 'contact.name') return name;
  if (token === 'contact.company') return sample?.company_name || '';
  return '';
};

/**
 * Text as the first person gets it ("Como o cliente vê"), filled in one left-to-right pass
 * (indexOf, no regular expressions); a field without value shows `placeholder(token)`.
 */
export const renderTokens = (
  text,
  { sample, extraColumns = [], defaults = {}, placeholder }
) => {
  const headerOf = Object.fromEntries(
    audienceColumnTokens(extraColumns).map(item => [item.token, item.header])
  );
  const source = String(text || '');
  let output = '';
  let position = 0;
  while (position < source.length) {
    const start = source.indexOf('{{', position);
    const finish = start === -1 ? -1 : source.indexOf('}}', start + 2);
    if (start === -1 || finish === -1) {
      output += source.slice(position);
      break;
    }
    output += source.slice(position, start);
    const token = source.slice(start + 2, finish).trim();
    const value = headerOf[token]
      ? sample?.extra_values?.[headerOf[token]]
      : contactValue(token, sample);
    output += value || defaults[token] || placeholder(token);
    position = finish + 2;
  }
  return output;
};
