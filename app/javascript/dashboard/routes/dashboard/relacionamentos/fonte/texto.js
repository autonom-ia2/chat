// #2894 — comparar texto digitado com nome, telefone e documento sem regex:
// sem acento, sem maiúscula, e número só com os dígitos.
const PRIMEIRA_MARCA_DE_ACENTO = 0x300;

const semMarca = char => char.charCodeAt(0) < PRIMEIRA_MARCA_DE_ACENTO;

export const semAcento = texto =>
  [...String(texto ?? '').normalize('NFD')].filter(semMarca).join('');

export const normalizado = texto => semAcento(texto).toLowerCase().trim();

export const soDigitos = texto =>
  [...String(texto ?? '')].filter(char => char >= '0' && char <= '9').join('');
