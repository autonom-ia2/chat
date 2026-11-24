import { attributeDate } from 'dashboard/helper/attributeDate';
import { DIA_EM_MS } from '../fonte/grupos';
import { normalizado } from '../fonte/texto';
import {
  JUNTAR,
  MODELOS,
  OPERADORES,
  TIPOS,
  condicoesProntas,
} from './informacoes';

// #3168 — as condições de "Por outra informação" avaliadas no navegador, só
// para a demonstração (`?demo=`): fora dela quem decide é o servidor, com a
// regra de `contacts/filter`. Aqui a regra é a mesma, do jeito mais simples:
// texto sem acento nem maiúscula, data pelo dia e quem não tem a informação
// não passa em "depois de", "antes de" nem "há mais de … dias".

// As da pessoa que moram em additional_attributes (como na ficha).
const NOS_ADICIONAIS = ['city', 'company_name', 'country_code'];

const valorNaPessoa = (pessoa, { chave, modelo }) => {
  if (modelo === MODELOS.DA_CONTA) return pessoa.custom_attributes?.[chave];
  if (NOS_ADICIONAIS.includes(chave)) {
    return pessoa.additional_attributes?.[chave];
  }
  return pessoa[chave];
};

const ausente = valor =>
  valor === undefined ||
  valor === null ||
  valor === '' ||
  (Array.isArray(valor) && !valor.length);

// O dia de uma data guardada em segundos (created_at, last_activity_at) ou já
// escrita "AAAA-MM-DD" (campo de data da conta), no fuso do navegador.
const doisDigitos = numero => String(numero).padStart(2, '0');
const diaDe = valor => {
  if (typeof valor === 'number') {
    const data = new Date(valor * 1000);
    return `${data.getFullYear()}-${doisDigitos(data.getMonth() + 1)}-${doisDigitos(data.getDate())}`;
  }
  return attributeDate(valor);
};
const momentoDe = valor =>
  typeof valor === 'number'
    ? valor * 1000
    : new Date(`${attributeDate(valor)}T00:00:00`).getTime();

const igual = (guardado, procurado) => {
  if (Array.isArray(guardado)) return guardado.includes(procurado);
  if (typeof procurado === 'boolean') return Boolean(guardado) === procurado;
  return normalizado(String(guardado ?? '')) === normalizado(String(procurado));
};

const contem = (guardado, procurado) =>
  normalizado(String(guardado ?? '')).includes(normalizado(String(procurado)));

const REGRAS = {
  [OPERADORES.TEM]: (guardado, valor) => contem(guardado, valor),
  [OPERADORES.NAO_TEM]: (guardado, valor) => !contem(guardado, valor),
  [OPERADORES.IGUAL]: (guardado, valor) => igual(guardado, valor),
  [OPERADORES.DIFERENTE]: (guardado, valor) => !igual(guardado, valor),
  [OPERADORES.DEPOIS]: (guardado, valor) =>
    !ausente(guardado) && diaDe(guardado) > valor,
  [OPERADORES.ANTES]: (guardado, valor) =>
    !ausente(guardado) && diaDe(guardado) < valor,
  [OPERADORES.HA_MAIS_DE_DIAS]: (guardado, valor, agora) =>
    !ausente(guardado) &&
    momentoDe(guardado) < agora - Number(valor) * DIA_EM_MS,
  [OPERADORES.PREENCHIDO]: guardado => !ausente(guardado),
  [OPERADORES.VAZIO]: guardado => ausente(guardado),
};

const textoDoValor = (tipo, valor) =>
  tipo === TIPOS.SIM_NAO || typeof valor !== 'string' ? valor : valor.trim();

export const pessoaPassaNaCondicao = (pessoa, condicao, agora = Date.now()) => {
  const regra = REGRAS[condicao.como];
  if (!regra) return true;
  return regra(
    valorNaPessoa(pessoa, condicao),
    textoDoValor(condicao.tipo, condicao.valor),
    agora
  );
};

// Só as linhas prontas contam; sem nenhuma, todo mundo passa.
export const pessoaPassaNasCondicoes = (
  pessoa,
  { condicoes = [], juntar = JUNTAR.TODAS } = {},
  agora = Date.now()
) => {
  const prontas = condicoesProntas(condicoes);
  if (!prontas.length) return true;
  const passa = condicao => pessoaPassaNaCondicao(pessoa, condicao, agora);
  return juntar === JUNTAR.QUALQUER
    ? prontas.some(passa)
    : prontas.every(passa);
};
