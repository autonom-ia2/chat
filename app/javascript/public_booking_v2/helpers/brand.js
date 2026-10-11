// Cor da marca da página (J2-A12, RA-20, #1289). Só #RRGGBB é aceito; qualquer outra coisa usa a cor padrão.
// A pessoa pode escolher qualquer cor, então a página trabalha com três valores:
//   --brand       a cor em versão legível sobre o branco (texto, bordas, foco): se a cor escolhida não tiver
//                 contraste AA (4,5:1) com o branco, escurecemos aos poucos até ter;
//   --brand-fill  a cor exatamente como a pessoa escolheu (fundo de botão e de selo);
//   --brand-on    o texto por cima do fundo: branco quando dá contraste AA, preto quando a cor é clara.
export const DEFAULT_BRAND_COLOR = '#1d4ed8';
export const LIGHT_TEXT = '#ffffff';
export const DARK_TEXT = '#000000';
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

// Contraste WCAG entre duas cores #RRGGBB (de 1 a 21).
export const contrastBetween = (hexA, hexB) => {
  const [lighter, darker] = [hexA, hexB]
    .map(hex => relativeLuminance(toChannels(hex)))
    .sort((a, b) => b - a);
  return (lighter + 0.05) / (darker + 0.05);
};

export const contrastWithWhite = hex => contrastBetween(hex, LIGHT_TEXT);

// Texto por cima da cor: branco sempre que passa no AA; senão preto, que nesse caso sempre passa (toda cor em que
// o branco fica abaixo de 4,5:1 tem pelo menos 4,6:1 com o preto).
export const textOnColor = hex =>
  contrastWithWhite(hex) >= MIN_CONTRAST ? LIGHT_TEXT : DARK_TEXT;

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

export const brandTokens = color => {
  const fill = isHexColor(color) ? color.toLowerCase() : DEFAULT_BRAND_COLOR;
  return { ink: readableBrandColor(color), fill, on: textOnColor(fill) };
};

export const applyBrandColor = (color, root = document.documentElement) => {
  const tokens = brandTokens(color);
  root.style.setProperty('--brand', tokens.ink);
  root.style.setProperty('--brand-fill', tokens.fill);
  root.style.setProperty('--brand-on', tokens.on);
  return tokens.ink;
};

// Alinhamento da logo no topo da página (#1289): esquerda é o padrão; valor desconhecido cai nele.
export const LOGO_ALIGNS = ['left', 'center', 'right'];
export const logoAlignOf = value =>
  LOGO_ALIGNS.includes(value) ? value : LOGO_ALIGNS[0];
