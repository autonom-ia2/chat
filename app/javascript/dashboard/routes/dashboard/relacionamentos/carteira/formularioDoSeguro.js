// #2897 — o formulário "Corrigir o seguro": do seguro para os campos, o que
// falta em cada campo e o que mudou, pronto para a fonte. Tudo função pura;
// nada que chega é alterado. Só é pedido o que o servidor pede: a seguradora e
// a data em que termina, e o número de quem já tinha número (o seguro que
// chegou sem número pode continuar sem). Início da vigência, valor e bem podem
// ficar em branco (e apagar um deles apaga o que estava guardado).
import {
  doCampoDeData,
  paraCampoDeData,
  valorDigitado,
  valorParaCampo,
} from './formatosDoSeguro';

export const OUTRA_SEGURADORA = '__outra__';

// A forma de comparação da seguradora. Espelha `Carteira::Chave.seguradora`
// (app/services/carteira/chave.rb): sem acento, em minúscula, só letra e
// dígito. O servidor manda um nome por forma de comparação ("Seguradora
// Exemplo S.A."), e o seguro pode ter outra grafia da mesma ("seguradora
// exemplo sa"): as duas são a mesma seguradora. O acento sai pela decomposição
// do Unicode (a letra fica, a marca cai no filtro); letra que o servidor
// translitera para duas (ß, æ) não tem par aqui e cai em "Outra".
const ehLetraOuDigito = char =>
  (char >= 'a' && char <= 'z') || (char >= '0' && char <= '9');
const decomposto = texto => String(texto ?? '').normalize('NFD');
export const chaveDaSeguradora = texto =>
  [...decomposto(texto).toLowerCase()].filter(ehLetraOuDigito).join('');

// O nome da lista que é a mesma seguradora do seguro, ou `undefined`.
const naLista = (seguradoras, nome) => {
  const chave = chaveDaSeguradora(nome);
  return seguradoras.find(outra => chaveDaSeguradora(outra) === chave);
};

export const formularioDoSeguro = (seguro, seguradoras = []) => {
  const conhecida = naLista(seguradoras, seguro.seguradora);
  return {
    tipo: seguro.tipo,
    seguradora: conhecida ?? OUTRA_SEGURADORA,
    outraSeguradora: conhecida ? '' : seguro.seguradora,
    numero: seguro.numero ?? '',
    comeca: paraCampoDeData(seguro.comeca),
    termina: paraCampoDeData(seguro.termina),
    valor: valorParaCampo(seguro.valor),
    bem: seguro.bem ?? '',
  };
};

// A ordem é a dos campos na tela: o foco vai para o primeiro que falta.
const ORDEM_DOS_CAMPOS = [
  'tipo',
  'seguradora',
  'outraSeguradora',
  'numero',
  'comeca',
  'termina',
  'valor',
  'bem',
];

const emBranco = texto => !String(texto ?? '').trim();

// campo -> chave do que falta (dentro de RELACIONAMENTOS_CARTEIRA.CORRIGIR.FALTA).
// `inicial` é o formulário como abriu.
export const faltasDoFormulario = (formulario, inicial) => {
  const comeca = doCampoDeData(formulario.comeca);
  const termina = doCampoDeData(formulario.termina);
  const faltas = [
    formulario.seguradora === OUTRA_SEGURADORA &&
      emBranco(formulario.outraSeguradora) && [
        'outraSeguradora',
        'OUTRA_SEGURADORA',
      ],
    emBranco(formulario.numero) &&
      !emBranco(inicial.numero) && ['numero', 'NUMERO'],
    !emBranco(formulario.comeca) && comeca === null && ['comeca', 'COMECA'],
    termina === null && ['termina', 'TERMINA'],
    comeca !== null &&
      termina !== null &&
      termina < comeca && ['termina', 'TERMINA_ANTES'],
    !emBranco(formulario.valor) &&
      valorDigitado(formulario.valor) === null && ['valor', 'VALOR'],
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
// nada mudou. Data e valor em branco vão como `null`: é assim que se apaga.
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
