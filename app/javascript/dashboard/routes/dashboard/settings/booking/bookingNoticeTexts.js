// Texto próprio de cada aviso (#1354). O texto salvo guarda as chaves do
// catálogo de campos na sintaxe `{{horario.data_hora}}` (a mesma do servidor,
// `Ai::Redacao::Chaves`); na tela a pessoa vê o rótulo leigo entre colchetes,
// `[Dia e hora do horário]`. Funções puras, sem regex: tudo por indexOf/split.

export const NOTICE_TEXT = {
  MAX_LENGTH: 500,
  NAME: 'cliente.primeiro_nome',
  WHEN: 'horario.data_hora',
  LINK: 'horario.link_gestao',
  BUSINESS: 'minha_empresa.nome',
};
export const NOTICE_TEXT_KEYS = [
  NOTICE_TEXT.NAME,
  NOTICE_TEXT.WHEN,
  NOTICE_TEXT.LINK,
  NOTICE_TEXT.BUSINESS,
];

const OPEN = '{{';
const CLOSE = '}}';

// [{ type: 'text' | 'key', value }] na ordem; `malformed` quando sobra `{{` ou
// `}}`, ou há `{` dentro de uma chave.
export const partsOf = text => {
  const source = String(text || '');
  const parts = [];
  let position = 0;
  let malformed = false;
  while (position < source.length) {
    const start = source.indexOf(OPEN, position);
    const end = start === -1 ? -1 : source.indexOf(CLOSE, start + OPEN.length);
    if (start === -1 || end === -1) break;
    if (start > position)
      parts.push({ type: 'text', value: source.slice(position, start) });
    // A chave vai exatamente como no catálogo: sem espaço e sem chave dentro.
    const key = source.slice(start + OPEN.length, end);
    const hasSpace = key.split('').some(char => !char.trim());
    if (!key || hasSpace || key.includes('{') || key.includes('}'))
      malformed = true;
    parts.push({ type: 'key', value: key });
    position = end + CLOSE.length;
  }
  if (position < source.length)
    parts.push({ type: 'text', value: source.slice(position) });
  // `}}` sobrando, ou `}` colado depois da chave (`{{a}}}`).
  const strayBraces = parts.some(
    (part, index) =>
      part.type === 'text' &&
      (part.value.includes(OPEN) ||
        part.value.includes(CLOSE) ||
        (index > 0 &&
          parts[index - 1].type === 'key' &&
          part.value.startsWith('}')))
  );
  return { parts, malformed: malformed || strayBraces };
};

export const keysOf = text =>
  partsOf(text)
    .parts.filter(part => part.type === 'key')
    .map(part => part.value);

// Chaves → rótulos entre colchetes, para a pessoa ler e editar.
export const toFriendly = (text, fields) =>
  partsOf(text)
    .parts.map(part => {
      if (part.type === 'text') return part.value;
      const field = fields.find(item => item.key === part.value);
      return field ? `[${field.label}]` : `${OPEN}${part.value}${CLOSE}`;
    })
    .join('');

// Rótulos entre colchetes → chaves. Colchete que não é rótulo fica como texto.
export const toKeys = (text, fields) => {
  const source = String(text || '');
  let result = '';
  let position = 0;
  while (position < source.length) {
    const start = source.indexOf('[', position);
    const end = start === -1 ? -1 : source.indexOf(']', start + 1);
    if (start === -1 || end === -1) break;
    const label = source.slice(start + 1, end).trim();
    const field = fields.find(item => item.label === label);
    result += source.slice(position, start);
    result += field
      ? `${OPEN}${field.key}${CLOSE}`
      : source.slice(start, end + 1);
    position = end + 1;
  }
  return result + source.slice(position);
};

// O mesmo que o servidor confere ao salvar (Notices::CustomText.problem).
// Devolve a chave do aviso em BOOKING.NOTICES.TEXTS.ERRORS ou null.
export const noticeTextProblem = text => {
  const value = String(text || '');
  if (!value.trim()) return 'BLANK';
  if (value.length > NOTICE_TEXT.MAX_LENGTH) return 'TOO_LONG';
  const { parts, malformed } = partsOf(value);
  if (malformed) return 'MALFORMED';
  // Colchete que sobrou é rótulo que não virou campo: iria cru ao cliente.
  if (value.includes('[') || value.includes(']')) return 'BRACKET';
  const keys = parts.filter(part => part.type === 'key').map(p => p.value);
  if (keys.some(key => !NOTICE_TEXT_KEYS.includes(key))) return 'UNKNOWN_FIELD';
  if (!keys.includes(NOTICE_TEXT.LINK)) return 'MISSING_LINK';
  if (!keys.includes(NOTICE_TEXT.WHEN)) return 'MISSING_WHEN';
  return null;
};

// Como o cliente vê: os campos trocados pelos exemplos e a linha de parar.
export const noticeTextPreview = (text, samples, stopLine) => {
  const body = partsOf(text)
    .parts.map(part =>
      part.type === 'key'
        ? (samples[part.value] ?? `{{${part.value}}}`)
        : part.value
    )
    .join('')
    .trim();
  return stopLine ? `${body}\n\n${stopLine}` : body;
};

// Só os textos escritos dos avisos que aparecem na tela (`kinds`, os do jogo);
// vazio volta ao padrão no servidor. Texto de aviso que saiu do jogo não vai:
// a pessoa não teria cartão para corrigir se ele fosse recusado.
export const noticeTextsPayload = (form, kinds) =>
  Object.fromEntries(
    Object.entries(form.noticeTexts || {}).filter(
      ([kind, text]) => kinds.includes(kind) && String(text || '').trim()
    )
  );

// Algum aviso do jogo com texto próprio que não serve: o passo não avança.
export const noticeTextsProblem = (form, kinds) =>
  kinds.some(kind => {
    const text = form.noticeTexts?.[kind];
    return text && noticeTextProblem(text);
  });
