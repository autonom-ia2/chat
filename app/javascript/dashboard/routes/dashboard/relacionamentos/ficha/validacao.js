// #2894 — conferência de e-mail e CPF sem expressão regular: só métodos de
// string e o cálculo dos dígitos verificadores.
import { soDigitos } from '../fonte/texto';

const TAMANHO_CPF = 11;
const BASE_DO_CPF = 9;
const MODULO_DO_CPF = 11;
const PRIMEIRO_PESO_DO_CPF = 10;

const temEspaco = texto => [...texto].some(char => char.trim() === '');

// Só olha o formato: um "@", algo antes, e um domínio com ponto no meio.
export const emailValido = texto => {
  const email = String(texto ?? '');
  if (!email || temEspaco(email)) return false;
  const partes = email.split('@');
  if (partes.length !== 2) return false;
  const [usuario, dominio] = partes;
  if (!usuario || dominio.includes('..')) return false;
  const pedacos = dominio.split('.');
  return pedacos.length >= 2 && pedacos.every(pedaco => pedaco.length > 0);
};

// Dígito verificador de uma sequência: pesos de `peso` descendo até 2.
const digitoVerificador = (digitos, peso) => {
  const soma = [...digitos].reduce(
    (total, char, i) => total + Number(char) * (peso - i),
    0
  );
  const resto = soma % MODULO_DO_CPF;
  return resto < 2 ? 0 : MODULO_DO_CPF - resto;
};

export const cpfValido = texto => {
  const digitos = soDigitos(texto);
  if (digitos.length !== TAMANHO_CPF) return false;
  if ([...digitos].every(char => char === digitos[0])) return false;
  const base = digitos.slice(0, BASE_DO_CPF);
  const primeiro = digitoVerificador(base, PRIMEIRO_PESO_DO_CPF);
  const segundo = digitoVerificador(
    `${base}${primeiro}`,
    PRIMEIRO_PESO_DO_CPF + 1
  );
  return digitos.endsWith(`${primeiro}${segundo}`);
};
