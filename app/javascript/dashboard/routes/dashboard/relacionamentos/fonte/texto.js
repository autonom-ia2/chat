// #2894 — comparar texto digitado com nome, telefone e documento sem regex:
// sem acento, sem maiúscula, e número só com os dígitos. Só as marcas
// combinantes (U+0300–U+036F, o que sobra do acento depois do NFD) saem: letra
// de outro alfabeto (cirílico, grego, CJK) fica.
const PRIMEIRA_MARCA_DE_ACENTO = 0x300;
const ULTIMA_MARCA_DE_ACENTO = 0x36f;

const semMarca = char => {
  const codigo = char.codePointAt(0);
  return codigo < PRIMEIRA_MARCA_DE_ACENTO || codigo > ULTIMA_MARCA_DE_ACENTO;
};

export const semAcento = texto =>
  [...String(texto ?? '').normalize('NFD')].filter(semMarca).join('');

export const normalizado = texto => semAcento(texto).toLowerCase().trim();

export const soDigitos = texto =>
  [...String(texto ?? '')].filter(char => char >= '0' && char <= '9').join('');
