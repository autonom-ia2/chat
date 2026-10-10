// Cor da marca da página (J2-A12, RA-20). Só #RRGGBB é aceito; qualquer outra coisa usa a cor padrão.
// Botões usam a cor como fundo com texto branco, então ela precisa de contraste AA (4,5:1) com o branco:
// se não tiver, escurecemos aos poucos até ter.
export const DEFAULT_BRAND_COLOR = '#1d4ed8';
const MIN_CONTRAST = 4.5;
const DARKEN_FACTOR = 0.9;
const MAX_DARKEN_STEPS = 40;
const HEX_DIGITS = '0123456789abcdef';

export const isHexColor = value =>
  typeof value === 'string' &&
  value.length === 7 &&
  value.startsWith('#') &&
  [...value.slice(1).toLowerCase()].every(char => HEX_DIGITS.includes(char));

const toChannels = hex =>
  [1, 3, 5].map(start => Number.parseInt(hex.slice(start, start + 2), 16));

const toHex = channels =>
  `#${channels.map(value => value.toString(16).padStart(2, '0')).join('')}`;

const relativeLuminance = channels => {
  const [r, g, b] = channels.map(value => {
    const s = value / 255;
    return s <= 0.03928 ? s / 12.92 : ((s + 0.055) / 1.055) ** 2.4;
  });
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
};

export const contrastWithWhite = hex =>
  1.05 / (relativeLuminance(toChannels(hex)) + 0.05);

export const readableBrandColor = color => {
  if (!isHexColor(color)) return DEFAULT_BRAND_COLOR;

  let channels = toChannels(color.toLowerCase());
  let steps = 0;
  while (contrastWithWhite(toHex(channels)) < MIN_CONTRAST) {
    if (steps >= MAX_DARKEN_STEPS) return DEFAULT_BRAND_COLOR;
    channels = channels.map(value => Math.floor(value * DARKEN_FACTOR));
    steps += 1;
  }
  return toHex(channels);
};

export const applyBrandColor = (color, root = document.documentElement) => {
  const value = readableBrandColor(color);
  root.style.setProperty('--brand', value);
  return value;
};
