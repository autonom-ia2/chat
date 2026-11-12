// #2894 — documentos fictícios da demonstração. Têm o formato de CPF e CNPJ,
// mas o primeiro dígito verificador é trocado de propósito: nenhum número daqui
// passa na conferência, então não pode ser de ninguém.
const MODULO = 11;

const somaPonderada = (digitos, pesos) =>
  pesos.reduce((soma, peso, i) => soma + Number(digitos[i]) * peso, 0);

const digitoVerificador = (digitos, pesos) => {
  const resto = somaPonderada(digitos, pesos) % MODULO;
  return resto < 2 ? 0 : MODULO - resto;
};

const PESOS_CPF_1 = [10, 9, 8, 7, 6, 5, 4, 3, 2];
const PESOS_CPF_2 = [11, 10, 9, 8, 7, 6, 5, 4, 3, 2];
const PESOS_CNPJ_1 = [5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2];
const PESOS_CNPJ_2 = [6, 5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2];

const comVerificadorTrocado = (base, pesos1, pesos2) => {
  const certo1 = digitoVerificador(base, pesos1);
  const certo2 = digitoVerificador(`${base}${certo1}`, pesos2);
  return `${base}${(certo1 + 1) % 10}${certo2}`;
};

const NOVE_DIGITOS = 9;
const BASE_MINIMA_CPF = 100_000_000;
const PASSO_CPF = 7919;
const FAIXA_CPF = 900_000_000;

// 11 dígitos, só números.
export const cpfFalso = n => {
  const base = String(BASE_MINIMA_CPF + ((n * PASSO_CPF) % FAIXA_CPF)).padStart(
    NOVE_DIGITOS,
    '0'
  );
  return comVerificadorTrocado(base, PESOS_CPF_1, PESOS_CPF_2);
};

const OITO_DIGITOS = 8;
const BASE_MINIMA_CNPJ = 10_000_000;
const PASSO_CNPJ = 104_729;
const FAIXA_CNPJ = 90_000_000;
const FILIAL_MATRIZ = '0001';

// 14 dígitos, só números.
export const cnpjFalso = n => {
  const raiz = String(
    BASE_MINIMA_CNPJ + ((n * PASSO_CNPJ) % FAIXA_CNPJ)
  ).padStart(OITO_DIGITOS, '0');
  return comVerificadorTrocado(
    `${raiz}${FILIAL_MATRIZ}`,
    PESOS_CNPJ_1,
    PESOS_CNPJ_2
  );
};
