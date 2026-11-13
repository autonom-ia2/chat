// #2898 — "Guardar a apólice nova": o formulário da apólice que substitui a do
// seguro que renovou, escrita à mão. Reusa as regras do "Corrigir o seguro"
// (carteira/formularioDoSeguro.js). Nasce com o que não muda de um ano para o
// outro (tipo, seguradora, o que está segurado) e com a vigência seguinte: a
// nova começa no dia em que a anterior termina e vale um ano. Número e valor
// ficam em branco: são da apólice nova. Tudo função pura.
import { paraCampoDeData } from './formatosDoSeguro';
import {
  dadosParaCorrigir,
  faltasDoFormulario,
  formularioDoSeguro,
} from './formularioDoSeguro';

const MS_POR_SEGUNDO = 1000;
const MEIO_DIA = 12;

// O mesmo dia, um ano depois (29 de fevereiro cai em 1º de março).
const umAnoDepois = segundos => {
  const dia = new Date(segundos * MS_POR_SEGUNDO);
  const depois = new Date(
    dia.getFullYear() + 1,
    dia.getMonth(),
    dia.getDate(),
    MEIO_DIA
  );
  return Math.floor(depois.getTime() / MS_POR_SEGUNDO);
};

export const formularioDaApoliceNova = (anterior, seguradoras = []) => ({
  ...formularioDoSeguro(anterior, seguradoras),
  numero: '',
  valor: '',
  comeca: paraCampoDeData(anterior.termina),
  termina: paraCampoDeData(umAnoDepois(anterior.termina)),
});

// A apólice nova sempre tem número: sem ele não dá para achá-la depois.
const SEMPRE_COM_NUMERO = { numero: 'obrigatorio' };
export const faltasDaApoliceNova = formulario =>
  faltasDoFormulario(formulario, SEMPRE_COM_NUMERO);

const EM_BRANCO = {
  tipo: '',
  seguradora: '',
  outraSeguradora: '',
  numero: '',
  comeca: '',
  termina: '',
  valor: '',
  bem: '',
};

// Tudo o que foi preenchido, no formato do seguro (datas em segundos, valor em
// número). O que ficou em branco não vai.
export const dadosDaApoliceNova = formulario =>
  dadosParaCorrigir(EM_BRANCO, formulario);
