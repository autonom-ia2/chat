// Modelo de teclado do padrão WAI-ARIA "select-only combobox", usado pelo ChoiceSelect.
// Puro para ser testado; o componente só traduz a ação devolvida em estado.
// Portado de bio-autonomia/src/lib/ui/choice-keys.ts.

const PAGE = 10;
const clamp = (value, count) =>
  Math.min(Math.max(value, 0), Math.max(count - 1, 0));

export const choiceKeyAction = ({
  key,
  altKey = false,
  open,
  active,
  selected,
  count,
}) => {
  if (count === 0) return { type: 'none' };
  const start = selected >= 0 ? selected : 0;
  if (!open) {
    if (['ArrowDown', 'ArrowUp', 'Enter', ' '].includes(key))
      return { type: 'open', active: start };
    if (key === 'Home') return { type: 'open', active: 0 };
    if (key === 'End') return { type: 'open', active: count - 1 };
    return { type: 'none' };
  }
  const current = active >= 0 ? active : start;
  if (key === 'ArrowUp' && altKey)
    return { type: 'commit', active: current, keepDefault: false };
  if (key === 'Enter' || key === ' ')
    return { type: 'commit', active: current, keepDefault: false };
  if (key === 'Tab')
    return { type: 'commit', active: current, keepDefault: true };
  if (key === 'Escape') return { type: 'close' };
  if (key === 'ArrowDown')
    return { type: 'move', active: clamp(current + 1, count) };
  if (key === 'ArrowUp')
    return { type: 'move', active: clamp(current - 1, count) };
  if (key === 'PageDown')
    return { type: 'move', active: clamp(current + PAGE, count) };
  if (key === 'PageUp')
    return { type: 'move', active: clamp(current - PAGE, count) };
  if (key === 'Home') return { type: 'move', active: 0 };
  if (key === 'End') return { type: 'move', active: count - 1 };
  return { type: 'none' };
};

// Sinais diacríticos combinantes (U+0300 a U+036F) que o NFD separa das letras.
const COMBINING_START = 0x300;
const COMBINING_END = 0x36f;
const isCombining = char => {
  const code = char.codePointAt(0);
  return code >= COMBINING_START && code <= COMBINING_END;
};

// "Ç" e "ç", "É" e "e" viram a mesma letra, para a busca por digitação.
export const foldForTypeahead = text =>
  [...text.normalize('NFD')]
    .filter(char => !isCombining(char))
    .join('')
    .toLowerCase();

// Busca pelo começo do rótulo a partir da opção seguinte a `from`;
// a mesma letra repetida alterna entre as opções que começam com ela.
export const typeaheadIndex = (labels, query, from) => {
  const folded = foldForTypeahead(query);
  if (!folded) return -1;
  const repeated =
    folded.length > 1 && [...folded].every(char => char === folded[0]);
  const needle = repeated ? folded[0] : folded;
  const offset = repeated || folded.length === 1 ? 1 : 0;
  for (let step = 0; step < labels.length; step += 1) {
    const index =
      (Math.max(from, -1) + offset + step + labels.length) % labels.length;
    if (foldForTypeahead(labels[index]).startsWith(needle)) return index;
  }
  return -1;
};
