// #3100 — as contas do cartão fidelidade e do cupom, sem tela. Tudo o que a
// tela precisa decidir sozinha (quantos carimbos uma compra dá, quanto falta
// para o prêmio, se o programa está pronto para salvar, como fica o código do
// cupom) mora aqui, para o servidor e a tela usarem a mesma régua.

export const TIPOS = { CARIMBOS: 'carimbos', PONTOS: 'pontos' };

// O cartão de carimbos precisa caber na tela do celular: até 20 bolinhas.
export const METAS_DE_CARIMBO = [5, 6, 8, 10, 12, 15, 20];
export const META_MAXIMA_DE_CARIMBOS = 20;
export const META_MAXIMA_DE_PONTOS = 100000;
export const PREMIO_MAXIMO = 80;
// "Valem para sempre" é `null`.
export const VALIDADES = [null, 3, 6, 12];

const inteiroPositivo = valor => Number.isInteger(valor) && valor > 0;
const escrito = texto => Boolean((texto || '').trim());

// A compra dá carimbos pelo valor dela, sem guardar troco: a cada R$ 50 numa
// compra de R$ 120, 2 carimbos (os R$ 20 não passam para a próxima).
export const carimbosDaCompra = (valor, programa) => {
  if (!programa || !inteiroPositivo(programa.a_cada)) return 0;
  if (!Number.isFinite(valor) || valor <= 0) return 0;
  return Math.floor(valor / programa.a_cada) * (programa.ganha || 1);
};

// Onde a pessoa está no cartão: quantos já tem (até a meta), quantos faltam,
// se completou, quantos prêmios cabem no saldo e o que sobra depois de um.
export const progresso = (saldo, meta) => {
  const tem = Math.max(0, Number.isInteger(saldo) ? saldo : 0);
  if (!inteiroPositivo(meta))
    return { tem, feitos: 0, faltam: 0, completo: false, premios: 0, sobra: 0 };
  return {
    tem,
    feitos: Math.min(tem, meta),
    faltam: Math.max(meta - tem, 0),
    completo: tem >= meta,
    premios: Math.floor(tem / meta),
    sobra: Math.max(tem - meta, 0),
  };
};

// Perto do prêmio: falta pouco (até 20% da meta, no mínimo 1).
export const pertoDoPremio = (saldo, meta) => {
  const { faltam, completo } = progresso(saldo, meta);
  if (completo || !inteiroPositivo(meta)) return false;
  return faltam <= Math.max(1, Math.floor(meta * 0.2));
};

// O que ainda falta para salvar o programa, pela ordem em que aparece na tela.
// Cada item é a chave do aviso (FIDELIDADE.MONTAR.ERROS.<chave>).
export const errosDoPrograma = programa => {
  const erros = [];
  if (!programa) return ['TUDO'];
  if (!inteiroPositivo(programa.a_cada)) erros.push('A_CADA');
  if (!inteiroPositivo(programa.ganha)) erros.push('GANHA');
  const teto =
    programa.tipo === TIPOS.PONTOS
      ? META_MAXIMA_DE_PONTOS
      : META_MAXIMA_DE_CARIMBOS;
  if (
    !inteiroPositivo(programa.meta) ||
    programa.meta < 2 ||
    programa.meta > teto
  )
    erros.push('META');
  if (
    !escrito(programa.premio) ||
    programa.premio.trim().length > PREMIO_MAXIMO
  )
    erros.push('PREMIO');
  return erros;
};

export const programaPronto = programa => !errosDoPrograma(programa).length;

// O cliente de exemplo das telas (montar e o aviso de saldo): alguém que já
// tem quase tudo, e uma compra que mostra que o troco não passa para a
// próxima. A compra nunca fica abaixo de R$ 100, para "a cada R$ 1" não virar
// "uma compra de R$ 2".
const COMPRA_MINIMA_DE_EXEMPLO = 100;
export const compraDeExemplo = programa =>
  Math.max(COMPRA_MINIMA_DE_EXEMPLO, Math.round((programa?.a_cada || 0) * 2.4));
export const saldoDeExemplo = programa => {
  const meta = programa?.meta;
  if (!Number.isInteger(meta) || meta < 2) return 0;
  return programa.tipo === TIPOS.PONTOS
    ? Math.round(meta * 0.64)
    : Math.max(1, meta - 3);
};

// O começo de um programa novo: o que serve à maioria dos negócios.
export const programaNovo = () => ({
  ligado: true,
  tipo: TIPOS.CARIMBOS,
  a_cada: 50,
  moeda: 'BRL',
  ganha: 1,
  meta: 10,
  premio: '',
  validade_meses: null,
});

// Trocar entre carimbos e pontos reajusta a meta para algo que faça sentido
// no outro jeito (10 carimbos viram 500 pontos e vice-versa).
export const trocarTipo = (programa, tipo) => {
  if (programa.tipo === tipo) return programa;
  if (tipo === TIPOS.PONTOS)
    return { ...programa, tipo, a_cada: 1, ganha: 1, meta: 500 };
  return { ...programa, tipo, a_cada: 50, ganha: 1, meta: 10 };
};

// ---------- cupom ----------

export const OFERTAS = {
  PORCENTAGEM: 'porcentagem',
  VALOR: 'valor',
  PRESENTE: 'presente',
};
export const VALIDADES_DO_CUPOM = [7, 15, 30, 60];
export const PREFIXO_MAXIMO = 8;
// O fim do código de exemplo. O de verdade o servidor sorteia, sem letras que
// se confundem (0 e O, 1 e I).
export const FIM_DE_EXEMPLO = '7KD2';

const ACENTOS = [0x300, 0x36f];
const letraOuNumero = letra =>
  (letra >= 'A' && letra <= 'Z') || (letra >= '0' && letra <= '9');

// O começo do código que a conta escolhe: maiúsculas, sem acento, só letra e
// número, até 8. Sem expressão regular.
export const prefixoLimpo = texto =>
  Array.from((texto || '').normalize('NFD').toUpperCase())
    .filter(letra => {
      const codigo = letra.charCodeAt(0);
      return codigo < ACENTOS[0] || codigo > ACENTOS[1];
    })
    .filter(letraOuNumero)
    .slice(0, PREFIXO_MAXIMO)
    .join('');

export const exemploDeCodigo = prefixo => {
  const limpo = prefixoLimpo(prefixo);
  return limpo ? `${limpo}-${FIM_DE_EXEMPLO}` : FIM_DE_EXEMPLO;
};

// O código que o atendente digita para conferir: sem espaços nas pontas nem no
// meio, em maiúsculas. Código é coisa de máquina, não frase de pessoa.
export const codigoDigitado = texto =>
  Array.from((texto || '').toUpperCase())
    .filter(letra => letra.trim())
    .join('');

export const errosDoCupom = cupom => {
  const erros = [];
  if (!cupom) return ['TUDO'];
  if (!escrito(cupom.nome)) erros.push('NOME');
  const { oferta } = cupom;
  if (oferta?.tipo === OFERTAS.PORCENTAGEM) {
    if (!inteiroPositivo(oferta.valor) || oferta.valor > 100)
      erros.push('OFERTA');
  } else if (oferta?.tipo === OFERTAS.VALOR) {
    if (!inteiroPositivo(oferta.valor)) erros.push('OFERTA');
  } else if (oferta?.tipo === OFERTAS.PRESENTE) {
    if (!escrito(oferta.texto)) erros.push('OFERTA');
  } else erros.push('OFERTA');
  if (!prefixoLimpo(cupom.prefixo)) erros.push('PREFIXO');
  if (!VALIDADES_DO_CUPOM.includes(cupom.validade_dias)) erros.push('VALIDADE');
  return erros;
};

export const cupomPronto = cupom => !errosDoCupom(cupom).length;

export const cupomNovo = () => ({
  nome: '',
  oferta: { tipo: OFERTAS.PORCENTAGEM, valor: 10, texto: '' },
  moeda: 'BRL',
  prefixo: '',
  validade_dias: 15,
  limite_por_cliente: 1,
});

// Quantos dos cupons mandados foram usados, em porcentagem inteira.
export const taxaDeUso = ({ mandados, usados } = {}) =>
  inteiroPositivo(mandados)
    ? Math.round(((usados || 0) / mandados) * 100)
    : null;

// O que o atendente vê ao conferir um código, pelo que o servidor respondeu.
export const ESTADOS_DO_CODIGO = ['valido', 'usado', 'vencido', 'nao_existe'];
export const TOM_DO_CODIGO = {
  valido: 'verde',
  usado: 'neutro',
  vencido: 'ambar',
  nao_existe: 'vermelho',
};

// A mensagem de exemplo: cada dado do texto vira o valor de exemplo dele
// (o mesmo `{$valor}` da Automação livre).
export const textoDeExemplo = (partes, exemplos) =>
  (partes || [])
    .map(parte =>
      typeof parte === 'string' ? parte : (exemplos[parte.$valor] ?? '')
    )
    .join('');

// Quantas bolinhas por linha no cartão de carimbos, para as linhas ficarem
// cheias (10 = 2 de 5; 12 = 2 de 6; 8 = 2 de 4).
export const colunasDoCartao = meta => {
  if (!inteiroPositivo(meta)) return 5;
  if (meta <= 6) return meta;
  if (meta % 5 === 0) return 5;
  if (meta % 6 === 0) return 6;
  if (meta % 4 === 0) return 4;
  return 5;
};
