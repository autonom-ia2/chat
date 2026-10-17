// Só emoji (#1702): mensagem com 1 a 3 emojis e nada mais aparece grande e sem balão,
// como no WhatsApp. Isto é forma visual, não interpretação do que a pessoa quis dizer.
// Conta caracteres visíveis com Intl.Segmenter (um emoji composto, como 👨‍👩‍👧 ou 🇧🇷,
// é um caractere só) e confere o primeiro código de cada um pelas listas abaixo.
// Sem expressão regular: blocos de pictogramas e listas explícitas de símbolos.

export const MAXIMO_DE_EMOJIS = 3;

// Blocos de pictogramas (rostos, mãos, bandeiras, tons de pele, objetos...).
const BLOCOS_DE_EMOJI = [
  [0x1f000, 0x1faff], // Mahjong, cartas, bandeiras, pictogramas, rostos, transporte, suplementares
];

const codigosDe = texto => Array.from(texto, letra => letra.codePointAt(0));

// Símbolos antigos que já são emoji sozinhos (✅ ❌ ⭐ ⚽ ☕ e os signos).
const EMOJI_POR_PADRAO = new Set(
  codigosDe(
    '☔☕♈♉♊♋♌♍♎♏♐♑♒♓♿⚓⚡⚪⚫⚽⚾⛄⛅⛎⛔⛪⛲⛳⛵⛺⛽✅✊✋✨❌❎❓❔❕❗➕➖➗➰➿⌚⌛⏩⏪⏫⏬⏰⏳◽◾⬛⬜⭐⭕'
  )
);

// Símbolos que só viram emoji com o seletor de emoji (VS16) logo depois: sozinhos,
// são texto (❤ ✔ ✖ ✳ ☺ © ™ ▶). ✓ (U+2713) não está em lista nenhuma: é sempre texto.
const EMOJI_COM_SELETOR = new Set(
  codigosDe(
    '☀☁☂☃☄★☎☑☘☝☠☢☣☦☪☮☯☸☹☺♀♂♟♠♣♥♦♨♻♾⚒⚔⚕⚖⚗⚙⚛⚜⚠⚧⚰⚱⛈⛏⛑⛓⛩⛰⛱⛴⛷⛸⛹✂✈✉✌✍✏✒✔✖✝✡✳✴❄❇❣❤➡©®‼⁉™ℹ↔↕↖↗↘↙↩↪⌨⏏⏭⏮⏯⏱⏲⏸⏹⏺Ⓜ▪▫▶◀◻◼⤴⤵⬅⬆⬇〰〽㊗㊙'
  )
);

// Seletor de apresentação emoji (VS16) e capa de tecla (1️⃣).
const SELETOR_EMOJI = 0xfe0f;
const CAPA_DE_TECLA = 0x20e3;
const BASES_DE_TECLA = new Set(codigosDe('0123456789#*'));

const noBloco = codigo =>
  BLOCOS_DE_EMOJI.some(([inicio, fim]) => codigo >= inicio && codigo <= fim);

const ehEmoji = caractere => {
  const [primeiro, segundo, ...resto] = codigosDe(caractere);
  if (noBloco(primeiro) || EMOJI_POR_PADRAO.has(primeiro)) return true;
  // O VS16 só conta logo depois de um pictograma: "a" + VS16 continua sendo "a".
  if (EMOJI_COM_SELETOR.has(primeiro)) return segundo === SELETOR_EMOJI;
  // Capa de tecla: 1️⃣ (dígito, VS16 opcional, capa).
  return (
    BASES_DE_TECLA.has(primeiro) && [segundo, ...resto].includes(CAPA_DE_TECLA)
  );
};

let segmentador;
const caracteres = texto => {
  segmentador ||= new Intl.Segmenter(undefined, { granularity: 'grapheme' });
  return Array.from(segmentador.segment(texto), parte => parte.segment);
};

// Quantos emojis a mensagem tem, se só tiver emoji (espaços não contam); senão 0.
export const contarSoEmojis = texto => {
  if (typeof texto !== 'string' || !texto.trim()) return 0;
  const visiveis = caracteres(texto).filter(parte => parte.trim() !== '');
  if (visiveis.length > MAXIMO_DE_EMOJIS) return 0;
  return visiveis.every(ehEmoji) ? visiveis.length : 0;
};

export const ehSoEmoji = texto => contarSoEmojis(texto) > 0;
