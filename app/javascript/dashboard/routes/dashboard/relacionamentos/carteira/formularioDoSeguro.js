// #2897 — o formulário "Corrigir o seguro": do seguro para os campos, o que
// falta em cada campo e o que mudou, pronto para a fonte. Tudo função pura;
// nada que chega é alterado.
import { DIAS_DA_RENOVACAO, diasParaTerminar } from '../fonte/selosDoSeguro';
import {
  doCampoDeData,
  paraCampoDeData,
  valorDigitado,
  valorParaCampo,
} from './formatosDoSeguro';

export const OUTRA_SEGURADORA = '__outra__';

export const formularioDoSeguro = (seguro, seguradoras = []) => {
  const conhecida = seguradoras.includes(seguro.seguradora);
  return {
    tipo: seguro.tipo,
    seguradora: conhecida ? seguro.seguradora : OUTRA_SEGURADORA,
    outraSeguradora: conhecida ? '' : seguro.seguradora,
    numero: seguro.numero,
    comeca: paraCampoDeData(seguro.comeca),
    termina: paraCampoDeData(seguro.termina),
    valor: valorParaCampo(seguro.valor),
    bem: seguro.bem ?? '',
  };
};

// A ordem é a dos campos na tela: o foco vai para o primeiro que falta.
export const ORDEM_DOS_CAMPOS = [
  'tipo',
  'seguradora',
  'outraSeguradora',
  'numero',
  'comeca',
  'termina',
  'valor',
  'bem',
];

// campo -> chave do que falta (dentro de RELACIONAMENTOS_CARTEIRA.CORRIGIR.FALTA).
export const faltasDoFormulario = formulario => {
  const comeca = doCampoDeData(formulario.comeca);
  const termina = doCampoDeData(formulario.termina);
  const valor = valorDigitado(formulario.valor);
  const faltas = [
    formulario.seguradora === OUTRA_SEGURADORA &&
      !formulario.outraSeguradora.trim() && [
        'outraSeguradora',
        'OUTRA_SEGURADORA',
      ],
    !formulario.numero.trim() && ['numero', 'NUMERO'],
    comeca === null && ['comeca', 'COMECA'],
    termina === null && ['termina', 'TERMINA'],
    comeca !== null &&
      termina !== null &&
      termina <= comeca && ['termina', 'TERMINA_ANTES'],
    (valor === null || valor <= 0) && ['valor', 'VALOR'],
  ].filter(Boolean);
  return Object.fromEntries(faltas);
};

export const primeiroCampoQueFalta = faltas =>
  ORDEM_DOS_CAMPOS.find(campo => campo in faltas) ?? null;

const seguradoraEscolhida = formulario =>
  formulario.seguradora === OUTRA_SEGURADORA
    ? formulario.outraSeguradora.trim()
    : formulario.seguradora;

// Só o que mudou em relação ao que abriu, no formato do seguro. Objeto vazio =
// nada mudou.
export const dadosParaCorrigir = (inicial, atual) => {
  const mudou = campo => inicial[campo] !== atual[campo];
  const candidatos = [
    mudou('tipo') && ['tipo', atual.tipo],
    seguradoraEscolhida(inicial) !== seguradoraEscolhida(atual) && [
      'seguradora',
      seguradoraEscolhida(atual),
    ],
    mudou('numero') && ['numero', atual.numero.trim()],
    mudou('comeca') && ['comeca', doCampoDeData(atual.comeca)],
    mudou('termina') && ['termina', doCampoDeData(atual.termina)],
    valorDigitado(inicial.valor) !== valorDigitado(atual.valor) && [
      'valor',
      valorDigitado(atual.valor),
    ],
    mudou('bem') && ['bem', atual.bem.trim()],
  ].filter(Boolean);
  return Object.fromEntries(candidatos);
};

// Depois de salvar: a data nova pôs o seguro dentro dos dias da renovação e
// ainda não há card? Então o card nasce na rotina de amanhã cedo.
export const cardNasceAmanha = (seguro, agora = Date.now()) => {
  const dias = diasParaTerminar(seguro, agora);
  return (
    !seguro.renovacao &&
    !seguro.canceladoEm &&
    !seguro.renovadoEm &&
    dias >= 0 &&
    dias <= DIAS_DA_RENOVACAO
  );
};
