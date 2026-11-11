// #2897 — o desenho da carteira fictícia: quem tem qual seguro. Só é carregado
// no ambiente de desenvolvimento (fonte/carteiraFonte.js).
//
// Tudo é inventado e sempre igual: 168 seguros dos 120 clientes da base do
// bloco A (84 pessoas com um, 24 com dois, 12 com três). Seguradoras, números
// de apólice e placas não existem. O plano não tem data: guarda "termina em N
// dias" (negativo = já terminou), e quem monta o seguro põe a data de hoje.
//
// Totais: 98 ativos · 22 em renovação · 4 renovados · 41 vencidos · 3
// cancelados. Vencem em até 7 dias: 5; 30: 17; 60: 22; 90: 31.
import { pessoas } from './base';
import { embaralhadoFixo, sorteioFixo } from './sorteioFixo';

export const SEGURADORAS = [
  'Seguradora Atlântica',
  'Horizonte Seguros',
  'Serra Azul Seguros',
  'Seguradora Aurora',
];
const [ATLANTICA, HORIZONTE, SERRA_AZUL, AURORA] = SEGURADORAS;
// A única que não veio do Agger: chegou pela planilha, sem PDF.
export const SEGURADORA_DA_PLANILHA = AURORA;
export const PLANILHA_DE_ORIGEM = 'Carteira 2026.xlsx';
export const EQUIPE = ['Bia Lunardelli', 'Caio Tavarone'];
const [BIA, CAIO] = EQUIPE;
export const FUNIL_DE_RENOVACAO = 'Renovação';
const ETAPAS_ABERTAS = ['A vencer', 'Cotando', 'Opções enviadas', 'Negociação'];
export const MOTIVOS = [
  'achou_caro',
  'outra_corretora',
  'vendeu_o_bem',
  'nao_respondeu',
];

const EMPRESA_SEGURADA = 23;
const SEMENTES = { donos: 131, situacoes: 149, tipos: 163, seguradoras: 181 };

// ---- os seguros com nome (as jornadas passam por eles) ----------------------

const NOMEADOS = [
  {
    id: 1,
    pessoaId: 23,
    tipo: 'auto',
    seguradora: ATLANTICA,
    numero: 'AT-000451',
    valor: 2760,
    dias: 18,
    bem: 'Carro hatch prata, placa FIC-0A23',
    placa: 'FIC-0A23',
    renovacao: {
      etapa: 'Opções enviadas',
      cuida: BIA,
      proposta: { valor: 2980.8, variacao: 8, enviadaPor: BIA, haDias: 5 },
    },
  },
  {
    id: 2,
    pessoaId: 23,
    tipo: 'residencial',
    seguradora: HORIZONTE,
    numero: 'HZ-002318',
    valor: 640,
    dias: 214,
    bem: 'Apartamento em São Paulo',
    endosso: { haDias: 6, campo: 'valor', antes: 610, depois: 640 },
  },
  {
    id: 3,
    pessoaId: 23,
    tipo: 'vida',
    seguradora: SERRA_AZUL,
    numero: 'SA-118802',
    valor: 1150,
    dias: 331,
    anos: 2,
  },
  {
    id: 107,
    pessoaId: 4,
    tipo: 'auto',
    seguradora: HORIZONTE,
    numero: 'HZ-004410',
    valor: 1980,
    dias: 3,
    renovacao: { etapa: 'Cotando', cuida: CAIO, cotando: true },
  },
  {
    id: 110,
    pessoaId: 117,
    tipo: 'vida',
    seguradora: SERRA_AZUL,
    numero: 'SA-120077',
    valor: 890,
    dias: 2,
    // Faltou um dado para cotar; quem atende sozinho já perguntou.
    renovacao: {
      etapa: 'A vencer',
      cuida: BIA,
      faltou: 'nascimento',
      perguntou: 'Nina',
    },
  },
  {
    id: 111,
    pessoaId: 29,
    tipo: 'residencial',
    seguradora: ATLANTICA,
    numero: 'AT-000903',
    valor: 520,
    dias: 5,
    renovacao: { etapa: 'A vencer', cuida: CAIO },
  },
  {
    id: 112,
    pessoaId: 24,
    tipo: 'auto',
    seguradora: ATLANTICA,
    numero: 'AT-001288',
    valor: 3410,
    dias: 6,
    renovacao: {
      etapa: 'Cotando',
      cuida: BIA,
      proposta: { valor: 3580.5, variacao: 5 },
    },
  },
  {
    id: 113,
    pessoaId: 105,
    tipo: 'auto',
    seguradora: HORIZONTE,
    numero: 'HZ-005160',
    valor: 2150,
    dias: 7,
    renovacao: {
      etapa: 'Opções enviadas',
      cuida: CAIO,
      proposta: {
        valor: 2085.5,
        variacao: -3,
        enviadaSozinha: true,
        haDias: 2,
      },
    },
  },
  {
    id: 104,
    pessoaId: 59,
    tipo: 'residencial',
    seguradora: SERRA_AZUL,
    numero: 'SA-119340',
    valor: 700,
    dias: 25,
    // Proposta pronta, pessoa sem telefone: não chega.
    renovacao: {
      etapa: 'Cotando',
      cuida: BIA,
      proposta: { valor: 735, variacao: 5 },
    },
  },
  {
    id: 105,
    pessoaId: 203,
    tipo: 'auto',
    seguradora: ATLANTICA,
    numero: 'AT-001502',
    valor: 2300,
    dias: 40,
    // Proposta pronta, pessoa não quer mensagens: não sai sozinha.
    renovacao: {
      etapa: 'Cotando',
      cuida: CAIO,
      proposta: { valor: 2369, variacao: 3 },
    },
  },
  {
    id: 102,
    pessoaId: 38,
    tipo: 'auto',
    seguradora: AURORA,
    numero: 'AU-77031',
    valor: 2050,
    dias: 4,
    renovadoHaDias: 3,
    duvidas: ['valor'],
    renovacao: { etapa: 'Renovado', cuida: BIA },
  },
  {
    id: 103,
    pessoaId: 41,
    tipo: 'auto',
    seguradora: HORIZONTE,
    numero: 'HZ-003975',
    valor: 1760,
    dias: -12,
    motivo: 'achou_caro',
  },
  {
    id: 101,
    pessoaId: 72,
    tipo: 'residencial',
    seguradora: ATLANTICA,
    numero: 'AT-000777',
    valor: 480,
    dias: 120,
    canceladoHaDias: 40,
  },
  {
    id: 106,
    empresaId: EMPRESA_SEGURADA,
    tipo: 'empresarial',
    seguradora: ATLANTICA,
    numero: 'AT-002044',
    valor: 6900,
    dias: 150,
  },
  {
    id: 108,
    pessoaId: 13,
    tipo: 'auto',
    seguradora: HORIZONTE,
    numero: 'HZ-006021',
    valor: 2480,
    dias: 200,
    parcelaHaDias: 10,
  },
  {
    id: 109,
    pessoaId: 48,
    tipo: 'auto',
    seguradora: ATLANTICA,
    numero: 'AT-002210',
    valor: 2190,
    dias: 362,
    apoliceNova: true,
  },
];

// Quem ainda não é cliente e tem o seguro em outra corretora. Não conta nos 168.
const DE_FORA = [
  {
    id: 120,
    pessoaId: 20,
    tipo: 'auto',
    seguradora: AURORA,
    numero: '',
    valor: null,
    dias: 101,
    deFora: true,
    corretora: 'Outra Corretora',
  },
];

// ---- os outros 152, gerados -------------------------------------------------

const serie = (quantos, inicio, passo) =>
  Array.from({ length: quantos }, (_, i) => inicio + i * passo);
const repetir = (valor, vezes) => Array.from({ length: vezes }, () => valor);
const naOrdem = (lista, semente) =>
  embaralhadoFixo(lista.length, semente).map(i => lista[i]);

const VENCE_EM_ATE_30 = [9, 11, 12, 14, 16, 19, 21, 23, 27, 29];
const VENCE_EM_ATE_60 = [33, 44, 52, 58];
const VENCE_EM_ATE_90 = [63, 66, 69, 72, 75, 78, 81, 85, 88];
const VENCE_DEPOIS = serie(84, 95, 3);
// Há quantos dias cada vencido terminou. Com o seguro 103 (12 dias), são 5 nos
// últimos 30 dias, 11 nos últimos 90 e 39 nos últimos 12 meses: os mesmos
// "não renovou" da tela de resultados.
const VENCIDOS_NO_ANO = [5, 14, 23, 29, ...serie(34, 41, 9)];
const VENCIDOS_ANTIGOS = [380, 410];
// O motivo de cada um, na mesma ordem. Com o 103 (achou caro), os motivos dos
// últimos 30 dias somam 2 · 1 · 1 · 1; dos 90, 5 · 3 · 1 · 2; do ano, 17 · 10 ·
// 5 · 7 (achou caro · outra corretora · vendeu o bem · não respondeu).
const MOTIVOS_NO_ANO = [
  ...['achou_caro', 'outra_corretora', 'vendeu_o_bem', 'nao_respondeu'],
  ...repetir('achou_caro', 3),
  ...repetir('outra_corretora', 2),
  'nao_respondeu',
  ...repetir('achou_caro', 12),
  ...repetir('outra_corretora', 7),
  ...repetir('vendeu_o_bem', 4),
  ...repetir('nao_respondeu', 5),
];
const PARCELAS_HA_DIAS = [12, 20];
const QUANTOS_ESPECIAIS = 5;

const emRenovacao = (dias, i) => {
  const etapa = ETAPAS_ABERTAS[i % ETAPAS_ABERTAS.length];
  return { dias, renovacao: { etapa, cuida: EQUIPE[i % EQUIPE.length] } };
};

// Os cinco primeiros "vence depois" ficam para os donos especiais (sem telefone
// e parcela atrasada); o resto é embaralhado.
const situacoesGeradas = () => {
  const ativosLonge = VENCE_DEPOIS.map(dias => ({ dias }));
  const sorteadas = [
    ...[...VENCE_EM_ATE_30, ...VENCE_EM_ATE_60].map(emRenovacao),
    ...VENCE_EM_ATE_90.map(dias => ({ dias })),
    ...ativosLonge.slice(QUANTOS_ESPECIAIS),
    {
      dias: 2,
      renovadoHaDias: 2,
      renovacao: { etapa: 'Renovado', cuida: BIA },
    },
    {
      dias: 6,
      renovadoHaDias: 4,
      renovacao: { etapa: 'Renovado', cuida: CAIO },
    },
    {
      dias: 10,
      renovadoHaDias: 6,
      renovacao: { etapa: 'Renovado', cuida: BIA },
    },
    ...VENCIDOS_NO_ANO.map((dias, i) => ({
      dias: -dias,
      motivo: MOTIVOS_NO_ANO[i],
    })),
    ...VENCIDOS_ANTIGOS.map(dias => ({ dias: -dias, motivo: 'nao_respondeu' })),
    { dias: 200, canceladoHaDias: 15 },
    { dias: 90, canceladoHaDias: 70 },
  ];
  return [
    ...ativosLonge.slice(0, QUANTOS_ESPECIAIS),
    ...naOrdem(sorteadas, SEMENTES.situacoes),
  ];
};

const TIPOS_GERADOS = naOrdem(
  [
    ...repetir('auto', 65),
    ...repetir('residencial', 42),
    ...repetir('vida', 28),
    ...repetir('empresarial', 17),
  ],
  SEMENTES.tipos
);
const SEGURADORAS_GERADAS = naOrdem(
  [
    ...repetir(ATLANTICA, 57),
    ...repetir(HORIZONTE, 47),
    ...repetir(SERRA_AZUL, 37),
    ...repetir(AURORA, 8),
  ],
  SEMENTES.seguradoras
);

const primeiroNome = pessoa => pessoa.name.split(' ')[0];

// Quem tem lugar marcado: os donos dos seguros com nome, quem responde pela
// empresa segurada, os clientes sem telefone e os dois da parcela atrasada.
const donosMarcados = clientes => {
  const comNome = new Set(NOMEADOS.map(s => s.pessoaId).filter(Boolean));
  const livre = pessoa => !comNome.has(pessoa.id);
  const daEmpresa = clientes.find(
    pessoa =>
      pessoa.company_id === EMPRESA_SEGURADA &&
      livre(pessoa) &&
      pessoa.phone_number
  );
  const semTelefone = clientes.filter(p => !p.phone_number);
  const jaUsados = new Set([
    ...comNome,
    daEmpresa.id,
    ...semTelefone.map(p => p.id),
  ]);
  const comParcela = ['Paula', 'Inês'].map(nome =>
    clientes.find(
      pessoa =>
        primeiroNome(pessoa) === nome &&
        !jaUsados.has(pessoa.id) &&
        pessoa.phone_number
    )
  );
  return { comNome, daEmpresa, semTelefone, comParcela };
};

// Um dono por seguro gerado, na ordem das situações: primeiro os especiais (um
// seguro cada), depois o sorteio: 11 pessoas com três, 23 com dois, 68 com um.
const TRES = 11;
const DOIS = 23;
const donosDosGerados = (clientes, marcados) => {
  const especiais = [...marcados.semTelefone, ...marcados.comParcela];
  const fora = new Set([
    ...marcados.comNome,
    marcados.daEmpresa.id,
    ...especiais.map(p => p.id),
  ]);
  const livres = naOrdem(
    clientes.filter(pessoa => !fora.has(pessoa.id)),
    SEMENTES.donos
  );
  const quantos = i => {
    if (i < TRES) return 3;
    return i < TRES + DOIS ? 2 : 1;
  };
  return [
    ...especiais.map(p => p.id),
    ...livres.flatMap((pessoa, i) => repetir(pessoa.id, quantos(i))),
  ];
};

const PRIMEIRO_ID_GERADO = 4;
const ULTIMO_ID_ANTES_DOS_NOMEADOS = 100;
const PRIMEIRO_ID_DEPOIS_DOS_NOMEADOS = 121;
const idGerado = ordem =>
  ordem <= ULTIMO_ID_ANTES_DOS_NOMEADOS - PRIMEIRO_ID_GERADO
    ? PRIMEIRO_ID_GERADO + ordem
    : PRIMEIRO_ID_DEPOIS_DOS_NOMEADOS +
      ordem -
      (ULTIMO_ID_ANTES_DOS_NOMEADOS - PRIMEIRO_ID_GERADO + 1);

const PREFIXOS = {
  [ATLANTICA]: 'AT',
  [HORIZONTE]: 'HZ',
  [SERRA_AZUL]: 'SA',
  [AURORA]: 'AU',
};
const numeroGerado = (seguradora, id) =>
  seguradora === AURORA
    ? `AU-${77100 + id}`
    : `${PREFIXOS[seguradora]}-${String(3000 + id * 17).padStart(6, '0')}`;

// Placas no formato novo, sempre com o prefixo fictício "FIC" e nunca com a
// letra "A" (a única com "A" é a do seguro 1).
const LETRAS_DA_PLACA = 'BCDEFGHJK';
const placaGerada = id => {
  const letra = LETRAS_DA_PLACA[Math.floor(id / 10) % LETRAS_DA_PLACA.length];
  return `FIC-${id % 10}${letra}${String(id % 100).padStart(2, '0')}`;
};

const MODELOS = ['hatch', 'sedã', 'SUV', 'picape'];
const CORES = ['prata', 'branco', 'preto', 'cinza', 'vermelho'];
const FAIXAS_DE_VALOR = {
  auto: [1400, 4200],
  residencial: [380, 980],
  vida: [600, 1900],
  empresarial: [2800, 9800],
};
const MULTIPLO_DO_VALOR = 10;
const VARIACOES = [4, 6, -2, 9];

const bemGerado = (tipo, id, cidade) => {
  if (tipo === 'auto') {
    const modelo = MODELOS[id % MODELOS.length];
    const cor = CORES[id % CORES.length];
    return `Carro ${modelo} ${cor}, placa ${placaGerada(id)}`;
  }
  if (tipo === 'residencial') {
    return `${id % 2 ? 'Casa' : 'Apartamento'} em ${cidade}`;
  }
  return tipo === 'empresarial' ? `Loja e estoque em ${cidade}` : '';
};

const comProposta = (renovacao, valor, ordem) => {
  if (!['Opções enviadas', 'Negociação'].includes(renovacao?.etapa)) {
    return renovacao;
  }
  const variacao = VARIACOES[ordem % VARIACOES.length];
  return {
    ...renovacao,
    proposta: {
      valor: Math.round(valor * (100 + variacao)) / 100,
      variacao,
      enviadaPor: renovacao.cuida,
      haDias: 2 + (ordem % 5),
    },
  };
};

const SITUACOES = situacoesGeradas();

// Renovado é sempre da seguradora da planilha (é por isso que falta a apólice
// nova); os outros pegam a próxima seguradora da fila embaralhada.
const SEGURADORA_DE_CADA = SITUACOES.reduce(
  ({ lista, usadas }, situacao) =>
    situacao.renovadoHaDias
      ? { lista: [...lista, SEGURADORA_DA_PLANILHA], usadas }
      : {
          lista: [...lista, SEGURADORAS_GERADAS[usadas]],
          usadas: usadas + 1,
        },
  { lista: [], usadas: 0 }
).lista;

const valorGerado = (tipo, sorteio) => {
  const [minimo, maximo] = FAIXAS_DE_VALOR[tipo];
  const bruto = minimo + sorteio() * (maximo - minimo);
  return Math.round(bruto / MULTIPLO_DO_VALOR) * MULTIPLO_DO_VALOR;
};

const gerados = (clientes, marcados) => {
  const cidadeDe = new Map(
    clientes.map(p => [p.id, p.additional_attributes?.city ?? 'São Paulo'])
  );
  const sorteio = sorteioFixo(SEMENTES.situacoes);
  const comParcela = marcados.comParcela.map(p => p.id);
  return donosDosGerados(clientes, marcados).map((pessoaId, ordem) => {
    const id = idGerado(ordem);
    const situacao = SITUACOES[ordem];
    const tipo = TIPOS_GERADOS[ordem];
    const seguradora = SEGURADORA_DE_CADA[ordem];
    const valor = valorGerado(tipo, sorteio);
    const parcela = comParcela.indexOf(pessoaId);
    return {
      ...situacao,
      id,
      pessoaId,
      tipo,
      seguradora,
      numero: numeroGerado(seguradora, id),
      valor,
      bem: bemGerado(tipo, id, cidadeDe.get(pessoaId)),
      placa: tipo === 'auto' ? placaGerada(id) : null,
      renovacao: comProposta(situacao.renovacao ?? null, valor, ordem),
      ...(parcela >= 0 ? { parcelaHaDias: PARCELAS_HA_DIAS[parcela] } : {}),
    };
  });
};

let guardado = null;

// O plano inteiro: os 168 da carteira e, à parte, o seguro de outra corretora.
export const planoDaCarteira = () => {
  if (guardado) return guardado;
  const clientes = pessoas().filter(p => p.contact_type === 'customer');
  const marcados = donosMarcados(clientes);
  const comDono = NOMEADOS.map(seguro =>
    seguro.empresaId ? { ...seguro, pessoaId: marcados.daEmpresa.id } : seguro
  );
  guardado = {
    daCarteira: [...comDono, ...gerados(clientes, marcados)].sort(
      (a, b) => a.id - b.id
    ),
    deFora: DE_FORA,
  };
  return guardado;
};
