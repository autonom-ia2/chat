// Modelo de teclado do padrão WAI-ARIA "select-only combobox", usado pelo ChoiceSelect.
// Puro para ser testado; o componente só traduz a ação devolvida em estado.
// Portado de bio-autonomia/src/lib/ui/choice-keys.ts.

const PAGE = 10;
const clamp = (value, count) =>
  Math.min(Math.max(value, 0), Math.max(count - 1, 0));

// Primeira opção habilitada a partir de `from`, andando `step` (1 ou -1).
const enabledFrom = (disabled, from, step, count) => {
  for (let index = from; index >= 0 && index < count; index += step) {
    if (!disabled[index]) return index;
  }
  return -1;
};

// Habilitada mais próxima de `target`, preferindo a direção do movimento;
// sem nenhuma, fica em `current`.
const nearestEnabled = (disabled, target, step, count, current) => {
  const ahead = enabledFrom(disabled, target, step, count);
  if (ahead >= 0) return ahead;
  const behind = enabledFrom(disabled, target, -step, count);
  return behind >= 0 ? behind : current;
};

// Validador das props: toda opção tem `value` e `label`.
export const isChoiceList = options =>
  options.every(option => 'value' in option && 'label' in option);

// Mesma comparação do v-model do <select> nativo (looseEqual do Vue para
// valores simples): 5 e '5' são a mesma escolha; null só casa com null.
export const sameChoice = (a, b) =>
  a === b || (a != null && b != null && String(a) === String(b));

export const choiceKeyAction = ({
  key,
  altKey = false,
  open,
  active,
  selected,
  count,
  disabled = [],
}) => {
  if (count === 0) return { type: 'none' };
  const firstEnabled = Math.max(enabledFrom(disabled, 0, 1, count), 0);
  const lastEnabled = enabledFrom(disabled, count - 1, -1, count);
  const end = lastEnabled >= 0 ? lastEnabled : count - 1;
  const start = selected >= 0 ? selected : firstEnabled;
  if (!open) {
    if (['ArrowDown', 'ArrowUp', 'Enter', ' '].includes(key))
      return { type: 'open', active: start };
    if (key === 'Home') return { type: 'open', active: firstEnabled };
    if (key === 'End') return { type: 'open', active: end };
    return { type: 'none' };
  }
  const current = active >= 0 ? active : start;
  const moveTo = (target, step) => ({
    type: 'move',
    active: nearestEnabled(
      disabled,
      clamp(target, count),
      step,
      count,
      current
    ),
  });
  if (key === 'ArrowUp' && altKey)
    return { type: 'commit', active: current, keepDefault: false };
  if (key === 'Enter' || key === ' ')
    return { type: 'commit', active: current, keepDefault: false };
  if (key === 'Tab')
    return { type: 'commit', active: current, keepDefault: true };
  if (key === 'Escape') return { type: 'close' };
  if (key === 'ArrowDown') {
    const next = enabledFrom(disabled, current + 1, 1, count);
    return { type: 'move', active: next >= 0 ? next : current };
  }
  if (key === 'ArrowUp') {
    const previous = enabledFrom(disabled, current - 1, -1, count);
    return { type: 'move', active: previous >= 0 ? previous : current };
  }
  if (key === 'PageDown') return moveTo(current + PAGE, -1);
  if (key === 'PageUp') return moveTo(current - PAGE, 1);
  if (key === 'Home') return { type: 'move', active: firstEnabled };
  if (key === 'End') return { type: 'move', active: end };
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
