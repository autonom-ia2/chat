export function selectDefinitions(definitions, configuration, surface) {
  const selection = configuration?.surfaces?.[surface];
  if (!selection || selection.mode === 'legacy') {
    return surface === 'contact_sidebar' ? definitions : [];
  }
  return definitions.filter(definition =>
    selection.ids.includes(definition.id)
  );
}

export function fieldValue(type, value) {
  if (value === '' || value === null || value === undefined) return null;
  return ['number', 'currency', 'percent'].includes(type)
    ? Number(value)
    : value;
}

// Only creation generates a key. Existing keys are always passed through unchanged.
export function attributeKey(name) {
  const ascii = [...name.normalize('NFKD').toLowerCase()];
  let key = '';
  ascii.forEach(char => {
    const code = char.codePointAt(0);
    if (code >= 768 && code <= 879) return;
    if ('abcdefghijklmnopqrstuvwxyz0123456789'.includes(char)) key += char;
    else if (key && !key.endsWith('_')) key += '_';
  });
  return key.endsWith('_') ? key.slice(0, -1) : key;
}
