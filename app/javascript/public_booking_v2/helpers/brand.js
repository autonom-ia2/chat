// Cor da marca da página (J2-A12, RA-20, #1289, #1295). Só #RRGGBB é aceito; qualquer outra coisa usa a cor padrão.
// A pessoa pode escolher qualquer cor e a página tem tema claro e escuro, então ela trabalha com quatro valores:
//   --brand-ink-light  a cor em versão legível no tema claro (texto, bordas, foco): se a cor escolhida não tiver
//                      contraste AA (4,5:1) com a superfície clara mais difícil, escurecemos aos poucos até ter;
//   --brand-ink-dark   o mesmo para o tema escuro: clareamos aos poucos, sem tirar a cor (azul-marinho vira azul-claro,
//                      não cinza), até passar com folga do AA sobre a superfície escura;
//   --brand-fill       a cor exatamente como a pessoa escolheu (fundo de botão e de selo), nos dois temas;
//   --brand-on         o texto por cima do fundo: branco quando dá contraste AA, preto quando a cor é clara.
// Quem escolhe entre as duas versões legíveis é o CSS, pelo tema (`--brand`, em assets/_booking-theme.scss): nenhum
// script decide tema, então nada pisca.
export const DEFAULT_BRAND_COLOR = '#1d4ed8';
export const LIGHT_TEXT = '#ffffff';
export const DARK_TEXT = '#000000';
// A superfície mais difícil de cada tema em que a cor da marca vira texto: `--bk-inset`, o fundo do botão secundário
// com o mouse em cima (no claro é a mais escura delas; no escuro, a mais clara). Passando nela, passa no cartão e no
// campo. Um teste confere que estes dois valores são os do arquivo de cores.
export const LIGHT_SURFACE = '#f0f0f3';
export const DARK_SURFACE = '#21242b';
const MIN_CONTRAST = 4.5;
// No escuro, texto colorido no limite do AA parece apagado: a cor é clareada até 6:1.
const DARK_THEME_CONTRAST = 6;
const DARKEN_FACTOR = 0.9;
const LIGHTEN_STEP = 0.04;
const MAX_STEPS = 40;
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

const darken = channels =>
  channels.map(value => Math.floor(value * DARKEN_FACTOR));

// Clarear mantendo o tom e a saturação: sobe só a luminosidade (HSL).
const toHsl = channels => {
  const [r, g, b] = channels.map(value => value / 255);
  const max = Math.max(r, g, b);
  const min = Math.min(r, g, b);
  const lightness = (max + min) / 2;
  if (max === min) return [0, 0, lightness];

  const delta = max - min;
  const saturation =
    lightness > 0.5 ? delta / (2 - max - min) : delta / (max + min);
  // Em que sexto do círculo de cores a cor está, pelo canal mais forte (empate: vale o último, que dá o mesmo tom).
  const sector = {
    [r]: (g - b) / delta + (g < b ? 6 : 0),
    [g]: (b - r) / delta + 2,
    [b]: (r - g) / delta + 4,
  }[max];
  return [sector / 6, saturation, lightness];
};

const fromHsl = ([hue, saturation, lightness]) => {
  const chroma = (1 - Math.abs(2 * lightness - 1)) * saturation;
  const channel = offset => {
    const position = (offset + hue * 12) % 12;
    const amount = Math.max(-1, Math.min(position - 3, 9 - position, 1));
    return Math.round((lightness - (chroma / 2) * amount) * 255);
  };
  return [0, 8, 4].map(channel);
};

const lighten = channels => {
  const [hue, saturation, lightness] = toHsl(channels);
  return fromHsl([hue, saturation, Math.min(1, lightness + LIGHTEN_STEP)]);
};

// Anda com a cor (escurecendo ou clareando) até ela ter o contraste pedido com a superfície.
const readableOn = (color, surface, step, fallback, target = MIN_CONTRAST) => {
  if (!isHexColor(color)) return fallback;

  let channels = toChannels(color.toLowerCase());
  let steps = 0;
  while (contrastBetween(toHex(channels), surface) < target) {
    if (steps >= MAX_STEPS) return fallback;
    channels = step(channels);
    steps += 1;
  }
  return toHex(channels);
};

export const readableBrandColor = color =>
  readableOn(color, LIGHT_SURFACE, darken, DEFAULT_BRAND_COLOR);

// A cor padrão, clareada para o tema escuro (calculada uma vez).
const DEFAULT_BRAND_COLOR_DARK = readableOn(
  DEFAULT_BRAND_COLOR,
  DARK_SURFACE,
  lighten,
  LIGHT_TEXT,
  DARK_THEME_CONTRAST
);

export const readableBrandColorDark = color =>
  readableOn(
    color,
    DARK_SURFACE,
    lighten,
    DEFAULT_BRAND_COLOR_DARK,
    DARK_THEME_CONTRAST
  );

export const brandTokens = color => {
  const fill = isHexColor(color) ? color.toLowerCase() : DEFAULT_BRAND_COLOR;
  return {
    ink: readableBrandColor(color),
    inkDark: readableBrandColorDark(color),
    fill,
    on: textOnColor(fill),
  };
};

export const applyBrandColor = (color, root = document.documentElement) => {
  const tokens = brandTokens(color);
  root.style.setProperty('--brand-ink-light', tokens.ink);
  root.style.setProperty('--brand-ink-dark', tokens.inkDark);
  root.style.setProperty('--brand-fill', tokens.fill);
  root.style.setProperty('--brand-on', tokens.on);
  return tokens.ink;
};

// Alinhamento da logo no topo da página (#1289): esquerda é o padrão; valor desconhecido cai nele.
export const LOGO_ALIGNS = ['left', 'center', 'right'];
export const logoAlignOf = value =>
  LOGO_ALIGNS.includes(value) ? value : LOGO_ALIGNS[0];

// Logo no tema escuro (#1295). O servidor diz de onde ela veio (`brand.logo_dark_source`):
//   'own'    há uma imagem própria para o escuro (enviada ou gerada): cada tema mostra a sua;
//   'same'   a logo de sempre já se lê no escuro: a mesma imagem nos dois temas;
//   'plate'  não há versão para o escuro: a logo de sempre aparece sobre uma placa clara. É também o caso de
//            qualquer valor que a página não conheça: nunca logo invisível.
export const LOGO_DARK_MODES = { OWN: 'own', SAME: 'same', PLATE: 'plate' };
export const logoDarkModeOf = ({ darkUrl, source }) => {
  if (darkUrl) return LOGO_DARK_MODES.OWN;
  return source === 'same' ? LOGO_DARK_MODES.SAME : LOGO_DARK_MODES.PLATE;
};
