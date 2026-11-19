// #2897 — o formulário "Corrigir o seguro": do seguro para os campos, o que
// falta em cada campo e o que mudou, pronto para a fonte. Tudo função pura;
// nada que chega é alterado. Só é pedido o que o servidor pede: a seguradora e
// a data em que termina, e o número de quem já tinha número (o seguro que
// chegou sem número pode continuar sem). Início da vigência, valor e bem podem
// ficar em branco (e apagar um deles apaga o que estava guardado).
// #3043 (E8.1) — os dados do segurado que a cotação da renovação pede:
// nascimento, sexo, CEP, placa e classe de bônus. Todos podem ficar em branco
// (e apagar um deles apaga o que estava guardado). O CEP e a placa ganham uma
// máscara simples enquanto a pessoa digita; o servidor recebe o CEP só com os
// dígitos e a placa em maiúsculas, sem traço.
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

// ---- os dados do segurado (#3043) -------------------------------------------

const ehDigito = char => char >= '0' && char <= '9';
const ehLetraMaiuscula = char => char >= 'A' && char <= 'Z';
const DIGITOS_DO_CEP = 8;
const ANTES_DO_TRACO_DO_CEP = 5;
const TAMANHO_DA_PLACA = 7;
const BONUS_MAXIMO = 10;
export const SEXOS = ['F', 'M'];

const soDigitos = texto => [...String(texto ?? '')].filter(ehDigito).join('');

// "12345678" ou "12345-6" -> "12345-678" / "12345-6": só dígitos, no máximo
// oito, com o traço depois do quinto.
export const cepComMascara = texto => {
  const digitos = soDigitos(texto).slice(0, DIGITOS_DO_CEP);
  const inicio = digitos.slice(0, ANTES_DO_TRACO_DO_CEP);
  const fim = digitos.slice(ANTES_DO_TRACO_DO_CEP);
  return fim ? `${inicio}-${fim}` : inicio;
};

// "abc-1d23" -> "ABC1D23": maiúsculas, só letras e dígitos, no máximo sete.
export const placaComMascara = texto =>
  [...String(texto ?? '').toUpperCase()]
    .filter(char => ehDigito(char) || ehLetraMaiuscula(char))
    .slice(0, TAMANHO_DA_PLACA)
    .join('');

// A classe de bônus digitada, de 0 a 10, ou null quando não é uma.
export const bonusDigitado = texto => {
  const limpo = String(texto ?? '').trim();
  if (!limpo || ![...limpo].every(ehDigito)) return null;
  const classe = Number(limpo);
  return classe <= BONUS_MAXIMO ? classe : null;
};

// O seguro de empresa não tem nascimento nem sexo do segurado.
export const temNascimentoESexo = seguro =>
  seguro?.segurado?.tipo !== 'empresa';

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
    nascimento: paraCampoDeData(seguro.nascimento),
    sexo: seguro.sexo ?? '',
    cep: cepComMascara(seguro.cep),
    placa: seguro.placa ?? '',
    bonus: String(seguro.bonus ?? ''),
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
  'nascimento',
  'sexo',
  'cep',
  'placa',
  'bonus',
];

const emBranco = texto => !String(texto ?? '').trim();

// campo -> chave do que falta (dentro de RELACIONAMENTOS_CARTEIRA.CORRIGIR.FALTA).
// `inicial` é o formulário como abriu.
// O nascimento que existe e não é de amanhã em diante (no relógio de quem lê,
// como o campo de data).
const MS_POR_SEGUNDO = 1000;
const nascimentoValido = (texto, agora) => {
  const nascimento = doCampoDeData(texto);
  const hoje = doCampoDeData(
    paraCampoDeData(Math.floor(agora / MS_POR_SEGUNDO))
  );
  return nascimento !== null && nascimento <= hoje;
};

// #3043 — o que falta nos dados do segurado: só o que foi escrito e não serve.
const faltasDoSegurado = (formulario, agora) => [
  !emBranco(formulario.nascimento) &&
    !nascimentoValido(formulario.nascimento, agora) && [
      'nascimento',
      'NASCIMENTO',
    ],
  !emBranco(formulario.cep) &&
    soDigitos(formulario.cep).length !== DIGITOS_DO_CEP && ['cep', 'CEP'],
  !emBranco(formulario.placa) &&
    placaComMascara(formulario.placa).length !== TAMANHO_DA_PLACA && [
      'placa',
      'PLACA',
    ],
  !emBranco(formulario.bonus) &&
    bonusDigitado(formulario.bonus) === null && ['bonus', 'BONUS'],
];

export const faltasDoFormulario = (formulario, inicial, agora = Date.now()) => {
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
    ...faltasDoSegurado(formulario, agora),
  ].filter(Boolean);
  return Object.fromEntries(faltas);
};

export const primeiroCampoQueFalta = faltas =>
  ORDEM_DOS_CAMPOS.find(campo => campo in faltas) ?? null;

const seguradoraEscolhida = formulario =>
  formulario.seguradora === OUTRA_SEGURADORA
    ? formulario.outraSeguradora.trim()
    : formulario.seguradora;

// #3043 — os dados do segurado que mudaram. Só quando o formulário que abriu
// os tem (a apólice nova não os escreve). Em branco vai `null`.
const doSeguradoParaCorrigir = (inicial, atual) => {
  if (!('cep' in inicial)) return [];
  const mudou = campo => inicial[campo] !== atual[campo];
  const ouNulo = valor => valor || null;
  return [
    mudou('nascimento') && ['nascimento', doCampoDeData(atual.nascimento)],
    mudou('sexo') && ['sexo', ouNulo(atual.sexo)],
    soDigitos(inicial.cep) !== soDigitos(atual.cep) && [
      'cep',
      ouNulo(soDigitos(atual.cep)),
    ],
    placaComMascara(inicial.placa) !== placaComMascara(atual.placa) && [
      'placa',
      ouNulo(placaComMascara(atual.placa)),
    ],
    bonusDigitado(inicial.bonus) !== bonusDigitado(atual.bonus) && [
      'bonus',
      bonusDigitado(atual.bonus),
    ],
  ];
};

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
    ...doSeguradoParaCorrigir(inicial, atual),
  ].filter(Boolean);
  return Object.fromEntries(candidatos);
};
