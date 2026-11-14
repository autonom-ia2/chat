// #2897 — a carteira fictícia de seguros. Só é carregada no ambiente de
// desenvolvimento (fonte/carteiraFonte.js, `import.meta.env.DEV`); em produção
// o arquivo nem entra no pacote.
//
// Tudo é inventado e sempre igual: três seguros com nome (os da pessoa das
// jornadas da ficha) e um para cada outro cliente da base fictícia
// (demo/base.js). Seguradoras, números de apólice e bens não existem. O desenho
// não tem data: guarda "termina em N dias" (negativo = já terminou), e cada
// seguro ganha a data de hoje ao ser montado. As datas ficam em segundos, ao
// meio-dia, como a fonte real entrega às peças. As escritas ficam na memória
// deste módulo e devolvem uma cópia nova: nada que chega é alterado.
// #2898 — alguns seguros gerados têm renovação: aberta no funil (Em renovação),
// renovada (Renovado) ou perdida, com o motivo. "Renovou", "Não renovou", o
// desfazer e a apólice nova escrita à mão também só ficam na memória. A
// história segue o servidor: nenhum passo some. Desfazer soma o passo "desfeito",
// dizer o motivo depois completa o passo "Não renovou" que já existia, e
// cancelar o seguro com a renovação aberta a fecha como "não renovou", com o
// motivo "cancelou".
import { empresas, pessoas } from './base';
import { RECUSADO } from '../carteira/recusas';
import { DIA_EM_MS } from '../fonte/grupos';

const MS_POR_SEGUNDO = 1000;
const SEGUNDOS_POR_DIA = DIA_EM_MS / MS_POR_SEGUNDO;
const DIAS_DO_ANO = 365;
const MEIO_DIA = 12;
const CHEGOU_HA_DIAS = 20;
const CHEGOU_DE_NOVO_HA_DIAS = 6;

export const SEGURADORAS = [
  'Seguradora Atlântica',
  'Horizonte Seguros',
  'Serra Azul Seguros',
  'Seguradora Aurora',
];
const [ATLANTICA, HORIZONTE, SERRA_AZUL] = SEGURADORAS;
const PLANILHA_DE_ORIGEM = 'Carteira 2026.xlsx';
// Quem "fez" as ações na demonstração: uma pessoa inventada da equipe.
const QUEM_FEZ = { id: 1, nome: 'Bia Lunardelli' };
// Quem cuida das renovações na conta fictícia.
const QUEM_CUIDA = [QUEM_FEZ, { id: 2, nome: 'Caio Montenegro' }];
export const EQUIPE = QUEM_CUIDA.map(({ nome }) => nome);

const PESSOA_DAS_JORNADAS = 23;
const PRIMEIRO_GERADO = 101;

// Como o tipo "veio escrito" na planilha de cada seguro gerado.
const RAMOS = {
  auto: 'Automóvel',
  residencial: 'Residencial',
  vida: 'Vida individual',
  empresarial: 'Empresarial',
  outro: 'Fiança locatícia',
};
const BENS = {
  auto: 'Carro de passeio',
  residencial: 'Apartamento',
  vida: '',
  empresarial: 'Loja',
  outro: '',
};
const VALORES = { auto: 2760, residencial: 640, vida: 1150, empresarial: 4200 };
const TIPOS_NA_FILA = [
  'auto',
  'residencial',
  'auto',
  'vida',
  'auto',
  'empresarial',
  'outro',
];
// Em quantos dias cada seguro gerado termina, em fila: há quem vença nesta
// semana, no mês, no trimestre, bem depois e quem já venceu.
const DIAS_NA_FILA = [
  3, 5, 12, 21, 27, 45, 62, 88, 120, 160, 200, 250, 290, 330, -1, -4, -12, -40,
  -90,
];
// Um em cada tantos seguros gerados está cancelado ou tem PDF; e, dos clientes
// que têm empresa, um em cada tantos tem o seguro no nome dela.
const CADA_QUANTOS = { cancelado: 17, comPdf: 3, daEmpresa: 4 };
const CANCELADO_HA_DIAS = 9;

// A renovação de alguns seguros gerados, pela posição na fila de dias
// (DIAS_NA_FILA): quem vence em 21 e em 45 dias está com a renovação aberta;
// quem vence em 27 já renovou; quem venceu ontem e há 40 dias não renovou.
const FUNIL_DA_RENOVACAO = 'Renovação';
const RENOVACAO_NA_FILA = {
  3: { etapa: 'A vencer' },
  5: { etapa: 'Em conversa' },
  4: { etapa: 'Proposta enviada', desfecho: 'renovou' },
  14: { etapa: 'A vencer', desfecho: 'nao_renovou', motivo: 'achou_caro' },
  17: {
    etapa: 'Em conversa',
    desfecho: 'nao_renovou',
    motivo: 'outra_corretora',
  },
};
const PRIMEIRO_CARD = 5000;
const PRIMEIRA_APOLICE_NOVA = 9000;
const RENOVACAO_NASCEU_HA_DIAS = 12;
const DESFECHO_HA_DIAS = 2;
const MOTIVO_ESCRITO = 'outro';
const MOTIVO_DO_CANCELAMENTO = 'cancelou';
// Os passos da história que contam que a renovação não renovou.
const PASSOS_DE_NAO_RENOVOU = ['nao_renovou', 'nao_renovou_outro'];

const NOMEADOS = [
  {
    id: 1,
    pessoaId: PESSOA_DAS_JORNADAS,
    tipo: 'auto',
    seguradora: ATLANTICA,
    numero: 'AT-000451',
    valor: 2760,
    dias: 18,
    bem: 'Carro hatch prata',
    temPdf: true,
  },
  {
    id: 2,
    pessoaId: PESSOA_DAS_JORNADAS,
    tipo: 'residencial',
    seguradora: HORIZONTE,
    numero: 'HZ-002318',
    valor: 640,
    dias: 214,
    bem: 'Apartamento em São Paulo',
    // Chegou de novo pela planilha, com o valor mudado.
    chegouDeNovo: { campo: 'valor', antes: 610, depois: 640 },
  },
  {
    id: 3,
    pessoaId: PESSOA_DAS_JORNADAS,
    tipo: 'vida',
    seguradora: SERRA_AZUL,
    numero: 'SA-118802',
    valor: null,
    dias: 331,
    semComeco: true,
  },
];

const emSegundos = ms => Math.floor(ms / MS_POR_SEGUNDO);
const ha = (agora, dias) => emSegundos(agora - dias * DIA_EM_MS);
// O meio-dia do dia que fica a `dias` de hoje, no relógio de quem olha.
const aoMeioDia = (agora, dias) => {
  const dia = new Date(agora + dias * DIA_EM_MS);
  return emSegundos(
    new Date(dia.getFullYear(), dia.getMonth(), dia.getDate(), MEIO_DIA)
  );
};

const daFila = (fila, ordem) => fila[ordem % fila.length];
const aCada = (quantos, ordem) => ordem % quantos === quantos - 1;

const numeroGerado = (seguradora, id) =>
  `${seguradora.slice(0, 2).toUpperCase()}-${String(id).padStart(6, '0')}`;

// A base garante clientes com empresa (demo/base.js): sempre há seguro no nome
// de alguma.
const comSeguroDaEmpresa = clientes =>
  new Set(
    clientes
      .filter(pessoa => pessoa.company_id)
      .filter((_, ordem) => aCada(CADA_QUANTOS.daEmpresa, ordem))
      .map(pessoa => pessoa.id)
  );

const gerados = todosOsClientes => {
  const clientes = todosOsClientes.filter(
    pessoa => pessoa.id !== PESSOA_DAS_JORNADAS
  );
  const daEmpresaDeQuem = comSeguroDaEmpresa(clientes);
  return clientes.map((pessoa, ordem) => {
    const id = PRIMEIRO_GERADO + ordem;
    const daEmpresa = daEmpresaDeQuem.has(pessoa.id);
    const tipo = daEmpresa ? 'empresarial' : daFila(TIPOS_NA_FILA, ordem);
    const seguradora = daFila(SEGURADORAS, ordem);
    const cancelado = aCada(CADA_QUANTOS.cancelado, ordem);
    return {
      id,
      pessoaId: pessoa.id,
      empresaId: daEmpresa ? pessoa.company_id : null,
      tipo,
      ramoOriginal: RAMOS[tipo],
      seguradora,
      numero: numeroGerado(seguradora, id),
      valor: VALORES[tipo] ?? null,
      dias: daFila(DIAS_NA_FILA, ordem),
      bem: BENS[tipo],
      temPdf: aCada(CADA_QUANTOS.comPdf, ordem),
      canceladoHaDias: cancelado ? CANCELADO_HA_DIAS : null,
      // Seguro cancelado não tem renovação.
      renovacao: cancelado
        ? null
        : (RENOVACAO_NA_FILA[ordem % DIAS_NA_FILA.length] ?? null),
      cuida: daFila(QUEM_CUIDA, ordem),
    };
  });
};

// ---- do desenho ao seguro ---------------------------------------------------

const resumoDaPessoa = pessoa => ({
  id: pessoa.id,
  name: pessoa.name,
  phone_number: pessoa.phone_number,
  opted_out_at: pessoa.opted_out_at,
  blocked: pessoa.blocked,
  contact_type: pessoa.contact_type,
  thumbnail: pessoa.thumbnail,
});

// O documento do segurado fica nulo, como no servidor.
const seguradoDe = (pessoa, empresa) =>
  empresa
    ? { tipo: 'empresa', id: empresa.id, nome: empresa.name, documento: null }
    : { tipo: 'pessoa', id: pessoa.id, nome: pessoa.name, documento: null };

// O que a renovação soma ao seguro, como o servidor manda: o card do funil
// (`renovacao`), quando renovou e o motivo de não ter renovado. Seguro sem
// renovação não ganha nada.
const daRenovacao = (item, agora) => {
  if (!item.renovacao) return {};
  const { etapa, desfecho = null, motivo = null } = item.renovacao;
  return {
    renovacao: {
      cardId: PRIMEIRO_CARD + item.id,
      funil: FUNIL_DA_RENOVACAO,
      etapa,
      desfecho,
      cuida: item.cuida.nome,
      cuidaId: item.cuida.id,
    },
    renovadoEm: desfecho === 'renovou' ? ha(agora, DESFECHO_HA_DIAS) : null,
    motivo,
    motivoEscrito: '',
    apoliceNova: false,
  };
};

const montar = (item, { gente, firmas }, agora) => {
  const pessoa = gente.get(item.pessoaId);
  const termina = aoMeioDia(agora, item.dias);
  return {
    id: item.id,
    pessoaId: item.pessoaId,
    pessoa: resumoDaPessoa(pessoa),
    segurado: seguradoDe(pessoa, firmas.get(item.empresaId)),
    tipo: item.tipo,
    ramoOriginal: item.ramoOriginal ?? null,
    seguradora: item.seguradora,
    numero: item.numero,
    valor: item.valor,
    bem: item.bem ?? '',
    comeca: item.semComeco ? null : termina - DIAS_DO_ANO * SEGUNDOS_POR_DIA,
    termina,
    origem: {
      tipo: 'planilha',
      arquivo: PLANILHA_DE_ORIGEM,
      em: ha(agora, CHEGOU_HA_DIAS),
    },
    temPdf: Boolean(item.temPdf),
    canceladoEm: item.canceladoHaDias ? ha(agora, item.canceladoHaDias) : null,
    corrigidoAMao: [],
    ...daRenovacao(item, agora),
  };
};

const desenho = agora => {
  const todas = pessoas(agora);
  const clientes = todas.filter(pessoa => pessoa.contact_type === 'customer');
  return {
    itens: [...NOMEADOS, ...gerados(clientes)],
    base: {
      gente: new Map(todas.map(pessoa => [pessoa.id, pessoa])),
      firmas: new Map(empresas(agora).map(empresa => [empresa.id, empresa])),
    },
  };
};

// ---- escritas (só na memória) ----------------------------------------------

// id do seguro -> { campos, feitos }
let escritas = new Map();
const SEM_ESCRITA = { campos: {}, feitos: [] };
// As apólices novas escritas à mão: seguros inteiros, na ordem em que entraram.
let novas = [];

export const esquecerEscritasDaCarteira = () => {
  escritas = new Map();
  novas = [];
};

const escritaDe = id => escritas.get(id) ?? SEM_ESCRITA;

const passo = (tipo, quando, extras = {}) => ({
  tipo,
  quando,
  quem: null,
  valores: {},
  acao: null,
  mudancas: null,
  ...extras,
});

// Guarda o que mudou no seguro e o passo da história que conta isso.
const escrever = (id, campos, tipo, agora, extras = {}) => {
  const atual = escritaDe(id);
  escritas = new Map(escritas).set(id, {
    campos: { ...atual.campos, ...campos },
    feitos: [
      ...atual.feitos,
      passo(tipo, emSegundos(agora), { quem: QUEM_FEZ, ...extras }),
    ],
  });
};

// ---- leituras ---------------------------------------------------------------

export const segurosDaCarteira = (agora = Date.now()) => {
  const { itens, base } = desenho(agora);
  const doDesenho = itens.map(item => montar(item, base, agora));
  return [...doDesenho, ...novas].map(seguro => ({
    ...seguro,
    ...escritaDe(seguro.id).campos,
  }));
};

export const seguroPorId = (id, agora = Date.now()) =>
  segurosDaCarteira(agora).find(seguro => seguro.id === id) ?? null;

const chegada = (seguro, agora) => {
  const { chegouDeNovo } = NOMEADOS.find(item => item.id === seguro.id) ?? {};
  return [
    chegouDeNovo
      ? passo('chegou_de_novo', ha(agora, CHEGOU_DE_NOVO_HA_DIAS), {
          mudancas: [chegouDeNovo],
        })
      : null,
    passo('chegou_planilha', seguro.origem.em),
  ].filter(Boolean);
};

// O que a renovação com que o seguro nasceu na demonstração conta: quando
// começou (e com quem) e, se já nasceu terminada, como. O que acontece depois
// (desfazer, fechar de novo) entra pelos passos guardados, sem tirar estes.
const passosDaRenovacao = (seguro, agora) => {
  const { itens } = desenho(agora);
  const { renovacao, cuida } = itens.find(item => item.id === seguro.id) ?? {};
  if (!renovacao) return [];
  const terminou = ha(agora, DESFECHO_HA_DIAS);
  const fimDoDesenho = {
    renovou: () => passo('renovou', terminou, { quem: QUEM_FEZ }),
    nao_renovou: () =>
      passo('nao_renovou', terminou, {
        quem: QUEM_FEZ,
        valores: { motivo: renovacao.motivo },
      }),
  }[renovacao.desfecho];
  return [
    fimDoDesenho?.(),
    passo('renovacao_card_nasceu', ha(agora, RENOVACAO_NASCEU_HA_DIAS), {
      valores: { cuida: cuida.nome },
    }),
  ].filter(Boolean);
};

const maisNovoPrimeiro = (a, b) => b.quando - a.quando;

// Do mais novo para o mais velho, como o servidor manda.
export const historiaDoSeguro = (id, agora = Date.now()) => {
  const seguro = seguroPorId(id, agora);
  if (!seguro) return [];
  const deSempre = [...escritaDe(id).feitos]
    .reverse()
    .concat(seguro.origem.tipo === 'manual' ? [] : chegada(seguro, agora));
  const daRenovacaoDele = passosDaRenovacao(seguro, agora);
  return daRenovacaoDele.length
    ? [...deSempre, ...daRenovacaoDele].sort(maisNovoPrimeiro)
    : deSempre;
};

// ---- ações ------------------------------------------------------------------

export const corrigir = (id, dados, agora = Date.now()) => {
  const antes = seguroPorId(id, agora);
  const campos = Object.keys(dados);
  const corrigidoAMao = [...new Set([...antes.corrigidoAMao, ...campos])];
  escrever(id, { ...dados, corrigidoAMao }, 'corrigido', agora, {
    valores: { campos },
    mudancas: campos.map(campo => ({
      campo,
      antes: antes[campo],
      depois: dados[campo],
    })),
  });
  return seguroPorId(id, agora);
};

// Cancelar o seguro com a renovação aberta fecha a renovação como "não
// renovou", com o motivo "cancelou": card de seguro cancelado não fica aberto.
// Desfazer o cancelamento não reabre a renovação.
export const cancelar = (id, agora = Date.now()) => {
  const antes = seguroPorId(id, agora);
  escrever(id, { canceladoEm: emSegundos(agora) }, 'cancelado', agora);
  if (antes.renovacao && !antes.renovacao.desfecho) {
    escrever(
      id,
      {
        renovacao: { ...antes.renovacao, desfecho: 'nao_renovou' },
        motivo: MOTIVO_DO_CANCELAMENTO,
        motivoEscrito: '',
      },
      'nao_renovou',
      agora,
      { valores: { motivo: MOTIVO_DO_CANCELAMENTO } }
    );
  }
  return seguroPorId(id, agora);
};

export const voltarAAtivo = (id, agora = Date.now()) => {
  escrever(id, { canceladoEm: null }, 'voltou_a_ativo', agora);
  return seguroPorId(id, agora);
};

// Como o servidor: só PDF. O que não é PDF volta recusado, com o código.
export const guardarPdf = (id, arquivo, agora = Date.now()) => {
  const nome = String(arquivo?.name ?? '').toLowerCase();
  if (!nome.endsWith('.pdf')) {
    throw Object.assign(new Error('O arquivo não é um PDF.'), {
      name: RECUSADO,
      codigo: 'tipo',
    });
  }
  escrever(id, { temPdf: true }, 'pdf_anexado', agora);
  return seguroPorId(id, agora);
};

export const tirarPdf = (id, agora = Date.now()) => {
  escrever(id, { temPdf: false }, 'pdf_tirado', agora);
  return seguroPorId(id, agora);
};

// ---- a renovação (#2898) -----------------------------------------------------

// "Renovou" e "Não renovou" fecham a renovação do seguro; o desfazer a reabre
// e conta na história o que foi desfeito.

const comDesfecho = (id, agora, desfecho) => ({
  ...seguroPorId(id, agora).renovacao,
  desfecho,
});

export const renovou = (id, _dados, agora = Date.now()) => {
  const campos = {
    renovacao: comDesfecho(id, agora, 'renovou'),
    renovadoEm: emSegundos(agora),
    motivo: null,
    motivoEscrito: '',
  };
  escrever(id, campos, 'renovou', agora);
  return seguroPorId(id, agora);
};

// O passo "Não renovou" com o motivo: o escrito à mão leva as palavras de quem
// escreveu.
const passoComMotivo = (motivo, texto) =>
  motivo === MOTIVO_ESCRITO
    ? { tipo: 'nao_renovou_outro', valores: { texto } }
    : { tipo: 'nao_renovou', valores: motivo ? { motivo } : {} };

// A renovação já estava perdida (alguém a fechou sem dizer o motivo): o motivo
// completa o passo "Não renovou" mais novo, sem criar outro.
const completarOMotivo = (id, campos, doPasso) => {
  const atual = escritaDe(id);
  const ultimo = atual.feitos.findLastIndex(feito =>
    PASSOS_DE_NAO_RENOVOU.includes(feito.tipo)
  );
  escritas = new Map(escritas).set(id, {
    campos: { ...atual.campos, ...campos },
    feitos: atual.feitos.map((feito, ordem) =>
      ordem === ultimo ? { ...feito, ...doPasso } : feito
    ),
  });
};

export const naoRenovou = (id, { motivo, texto = '' }, agora = Date.now()) => {
  const antes = seguroPorId(id, agora);
  const campos = {
    renovacao: comDesfecho(id, agora, 'nao_renovou'),
    renovadoEm: null,
    motivo: motivo ?? null,
    motivoEscrito: motivo === MOTIVO_ESCRITO ? texto : '',
  };
  const { tipo, valores } = passoComMotivo(motivo, texto);
  if (antes.renovacao?.desfecho === 'nao_renovou') {
    completarOMotivo(id, campos, { tipo, valores });
  } else {
    escrever(id, campos, tipo, agora, { valores });
  }
  return seguroPorId(id, agora);
};

export const desfazerDesfecho = (id, _dados, agora = Date.now()) => {
  const anterior = seguroPorId(id, agora).renovacao?.desfecho;
  const campos = {
    renovacao: comDesfecho(id, agora, null),
    renovadoEm: null,
    motivo: null,
    motivoEscrito: '',
  };
  escrever(id, campos, 'desfez_desfecho', agora, { valores: { anterior } });
  return seguroPorId(id, agora);
};

// A apólice nova do seguro que renovou: um seguro novo, da mesma pessoa, que
// começa a valer. O anterior passa a dizer que já tem a apólice nova. Devolve o
// seguro NOVO, como o servidor.
export const apoliceNova = (id, dados, agora = Date.now()) => {
  const anterior = seguroPorId(id, agora);
  const novoId = PRIMEIRA_APOLICE_NOVA + novas.length;
  const nova = {
    ...anterior,
    ...dados,
    id: novoId,
    origem: { tipo: 'manual', arquivo: null, em: emSegundos(agora) },
    temPdf: false,
    canceladoEm: null,
    corrigidoAMao: [],
    renovacao: null,
    renovadoEm: null,
    motivo: null,
    motivoEscrito: '',
    apoliceNova: false,
  };
  novas = [...novas, nova];
  escrever(novoId, {}, 'apolice_nova', agora, {
    valores: { anterior: anterior.numero },
  });
  const atual = escritaDe(id);
  escritas = new Map(escritas).set(id, {
    ...atual,
    campos: { ...atual.campos, apoliceNova: true },
  });
  return seguroPorId(novoId, agora);
};

export const demoDaCarteira = {
  segurosDaCarteira,
  seguroPorId,
  historiaDoSeguro,
  corrigir,
  cancelar,
  voltarAAtivo,
  guardarPdf,
  tirarPdf,
  renovou,
  naoRenovou,
  desfazerDesfecho,
  apoliceNova,
};
