// #2897 — a carteira fictícia de seguros. Só é carregada no ambiente de
// desenvolvimento (fonte/carteiraFonte.js, `import.meta.env.DEV`).
//
// O desenho (quem tem o quê) vem de carteiraPlano.js; aqui cada seguro ganha as
// datas de hoje e os dados da pessoa da base do bloco A. As escritas ficam na
// memória deste módulo, para a tela refletir o que foi feito, e devolvem uma
// cópia nova: nada que chega é alterado.
import { empresas, pessoas } from './base';
import { comOsAjustes, esquecerAjustesDaDemo } from './carteiraAjustes';
import { cpfFalso } from './documentosFalsos';
import { historiaDaDemo } from './carteiraHistoria';
import { arquivosDeExemplo, lerDeFora } from './seguroDeFora';
import {
  FUNIL_DE_RENOVACAO,
  PLANILHA_DE_ORIGEM,
  SEGURADORA_DA_PLANILHA,
  planoDaCarteira,
} from './carteiraPlano';
import { DIA_EM_MS } from '../fonte/grupos';
import { soDigitos } from '../fonte/texto';

const SEGUNDOS_POR_DIA = DIA_EM_MS / 1000;
const DIAS_DO_ANO = 365;
const CHEGOU_DO_AGGER_HA_DIAS = 8;
const CHEGOU_DA_PLANILHA_HA_DIAS = 20;
const DIAS_DO_LEMBRETE = 60;
const AUMENTO_DA_APOLICE_NOVA = 1.03;
const SALTO_DO_NUMERO_NOVO = 1000;

export const emSegundos = ms => Math.floor(ms / 1000);
const daquiA = (agora, dias) => emSegundos(agora + dias * DIA_EM_MS);
const ha = (agora, dias) => (dias ? daquiA(agora, -dias) : null);

// ---- do plano ao seguro -----------------------------------------------------

const origemDe = (item, agora) =>
  item.seguradora === SEGURADORA_DA_PLANILHA
    ? {
        tipo: 'planilha',
        arquivo: PLANILHA_DE_ORIGEM,
        em: ha(agora, CHEGOU_DA_PLANILHA_HA_DIAS),
      }
    : { tipo: 'agger', em: ha(agora, CHEGOU_DO_AGGER_HA_DIAS) };

const resumoDaPessoa = pessoa => ({
  id: pessoa.id,
  name: pessoa.name,
  phone_number: pessoa.phone_number,
  opted_out_at: pessoa.opted_out_at,
  blocked: pessoa.blocked,
  contact_type: pessoa.contact_type,
  thumbnail: pessoa.thumbnail,
});

const seguradoDe = (item, pessoa, empresa) =>
  empresa
    ? {
        tipo: 'empresa',
        id: empresa.id,
        nome: empresa.name,
        documento: empresa.cnpj,
      }
    : {
        tipo: 'pessoa',
        id: pessoa.id,
        nome: pessoa.name,
        documento: pessoa.custom_attributes?.cpf ?? cpfFalso(pessoa.id),
      };

const renovacaoDe = (item, agora) => {
  if (!item.renovacao) return null;
  const { proposta } = item.renovacao;
  return {
    funil: FUNIL_DE_RENOVACAO,
    cotando: false,
    ...item.renovacao,
    proposta: proposta
      ? {
          valor: proposta.valor,
          variacao: proposta.variacao,
          enviadaPor: proposta.enviadaPor ?? null,
          enviadaSozinha: Boolean(proposta.enviadaSozinha),
          enviadaEm: ha(agora, proposta.haDias),
        }
      : null,
  };
};

const montar = (item, { gente, firmas }, agora) => {
  const pessoa = gente.get(item.pessoaId);
  const empresa = item.empresaId ? firmas.get(item.empresaId) : null;
  const termina = daquiA(agora, item.dias);
  const origem = origemDe(item, agora);
  return {
    id: item.id,
    pessoaId: item.pessoaId,
    pessoa: resumoDaPessoa(pessoa),
    segurado: seguradoDe(item, pessoa, empresa),
    tipo: item.tipo,
    seguradora: item.seguradora,
    numero: item.numero,
    valor: item.valor,
    bem: item.bem ?? '',
    placa: item.placa ?? null,
    comeca: termina - (item.anos ?? 1) * DIAS_DO_ANO * SEGUNDOS_POR_DIA,
    termina,
    origem,
    temPdf: origem.tipo === 'agger' && !item.deFora,
    canceladoEm: ha(agora, item.canceladoHaDias),
    renovadoEm: ha(agora, item.renovadoHaDias),
    motivo: item.motivo ?? null,
    parcelaAbertaEm: ha(agora, item.parcelaHaDias),
    renovacao: renovacaoDe(item, agora),
    endosso: item.endosso
      ? { ...item.endosso, em: ha(agora, item.endosso.haDias) }
      : null,
    apoliceNova: Boolean(item.apoliceNova),
    deFora: Boolean(item.deFora),
    corretora: item.corretora ?? '',
    lembreteEm: item.deFora
      ? termina - DIAS_DO_LEMBRETE * SEGUNDOS_POR_DIA
      : null,
    corrigidoAMao: [],
    // O que chegou com dúvida e pede conferência ("Confira").
    duvidas: item.duvidas ?? [],
  };
};

// ---- escritas (só na memória) ----------------------------------------------

// id do seguro -> { campos, feitos, antesDoPdf }
let escritas = new Map();
// Os seguros de outra corretora guardados na demonstração (Tela 20).
let guardadosDeFora = [];
const PRIMEIRO_GUARDADO_DE_FORA = 9001;

export const esquecerEscritasDaCarteira = () => {
  escritas = new Map();
  guardadosDeFora = [];
  esquecerAjustesDaDemo();
};

const SEM_ESCRITA = { campos: {}, feitos: [], antesDoPdf: null };

// Exportadas para as escritas da renovação (demo/carteiraRenovacao.js).
export const escritaDe = id => escritas.get(id) ?? SEM_ESCRITA;

export const escrever = (id, mudanca) => {
  const atual = escritaDe(id);
  escritas = new Map(escritas).set(id, { ...atual, ...mudanca(atual) });
};

// Volta a escrita de um seguro para como estava num momento guardado.
export const reporEscrita = (id, anterior) => {
  escritas = new Map(escritas).set(id, anterior);
};

// O que foi escrito e, por cima, o que os ajustes da conta mudam (a proposta
// que sai sozinha, o texto em palavras simples).
const comEscritas = seguro =>
  comOsAjustes({ ...seguro, ...escritaDe(seguro.id).campos });

export const feito = (atual, tipo, agora, valores = {}) => [
  ...atual.feitos,
  { tipo, quando: emSegundos(agora), valores },
];

// ---- leituras ---------------------------------------------------------------

const contexto = agora => ({
  gente: new Map(pessoas(agora).map(pessoa => [pessoa.id, pessoa])),
  firmas: new Map(empresas(agora).map(empresa => [empresa.id, empresa])),
});

// O que a pessoa guardou diz quando termina (não "daqui a tantos dias").
const montarGuardado = ({ termina, ...item }, base, agora) => ({
  ...montar(
    { ...item, dias: 0, deFora: true, numero: '', valor: null },
    base,
    agora
  ),
  termina,
  comeca: termina - DIAS_DO_ANO * SEGUNDOS_POR_DIA,
  lembreteEm: termina - DIAS_DO_LEMBRETE * SEGUNDOS_POR_DIA,
});

const originais = agora => {
  const plano = planoDaCarteira();
  const base = contexto(agora);
  return {
    daCarteira: plano.daCarteira.map(item => montar(item, base, agora)),
    deFora: [
      ...plano.deFora.map(item => montar(item, base, agora)),
      ...guardadosDeFora.map(item => montarGuardado(item, base, agora)),
    ],
  };
};

// Os 168 da carteira (sem o de outra corretora), já com o que foi escrito.
export const segurosDaCarteira = (agora = Date.now()) =>
  originais(agora).daCarteira.map(comEscritas);

// Tudo que a ficha de uma pessoa mostra: os dela e o de outra corretora.
export const segurosComOsDeFora = (agora = Date.now()) => {
  const { daCarteira, deFora } = originais(agora);
  return [...daCarteira, ...deFora].map(comEscritas);
};

const original = (id, agora) => {
  const { daCarteira, deFora } = originais(agora);
  return [...daCarteira, ...deFora].find(seguro => seguro.id === id) ?? null;
};

export const seguroPorId = (id, agora = Date.now()) => {
  const achado = original(id, agora);
  return achado ? comEscritas(achado) : null;
};

export const historiaDoSeguro = (id, agora = Date.now()) => {
  const seguro = seguroPorId(id, agora);
  return seguro ? historiaDaDemo(seguro, escritaDe(id).feitos, agora) : [];
};

// ---- o que o PDF diz --------------------------------------------------------

const numeroNovo = numero => {
  const [prefixo, digitos] = numero.split('-');
  const proximo = Number(soDigitos(digitos)) + SALTO_DO_NUMERO_NOVO;
  return `${prefixo}-${String(proximo).padStart(digitos.length, '0')}`;
};

// No renovado o PDF é a apólice nova: outro número, mais um ano e outro valor.
// Nos outros, o PDF diz o que chegou da seguradora, antes de qualquer correção.
const oQueOPdfDiz = (seguro, comoChegou) =>
  seguro.renovadoEm
    ? {
        numero: numeroNovo(seguro.numero),
        comeca: seguro.termina,
        termina: seguro.termina + DIAS_DO_ANO * SEGUNDOS_POR_DIA,
        valor: Math.round(seguro.valor * AUMENTO_DA_APOLICE_NOVA),
      }
    : Object.fromEntries(
        seguro.corrigidoAMao.map(campo => [campo, comoChegou[campo]])
      );

const mudancasDoPdf = (seguro, comoChegou) =>
  Object.entries(oQueOPdfDiz(seguro, comoChegou))
    .filter(([campo, noPdf]) => seguro[campo] !== noPdf)
    .map(([campo, noPdf]) => ({
      campo,
      antes: seguro[campo],
      noPdf,
      corrigidoAMao: seguro.corrigidoAMao.includes(campo),
    }));

const erroComNome = (name, mensagem) =>
  Object.assign(new Error(mensagem), { name });

const conferirArquivo = arquivo => {
  const nome = String(arquivo?.name ?? '').toLowerCase();
  if (!nome.endsWith('.pdf')) {
    throw erroComNome('NAO_E_APOLICE', 'Este arquivo não é um PDF de apólice.');
  }
  if (nome.includes('ilegivel')) {
    throw erroComNome('NAO_LEU', 'Não consegui ler este PDF.');
  }
};

export const lerPdf = (id, arquivo, agora = Date.now()) => {
  conferirArquivo(arquivo);
  const seguro = seguroPorId(id, agora);
  return {
    apoliceNova: Boolean(seguro.renovadoEm),
    mudancas: mudancasDoPdf(seguro, original(id, agora)),
  };
};

// ---- ações ------------------------------------------------------------------

export const corrigir = (id, dados, agora = Date.now()) => {
  const campos = Object.keys(dados);
  escrever(id, atual => ({
    campos: {
      ...atual.campos,
      ...dados,
      corrigidoAMao: [
        ...new Set([...(atual.campos.corrigidoAMao ?? []), ...campos]),
      ],
    },
    feitos: feito(atual, 'corrigido', agora, { campos }),
  }));
  return seguroPorId(id, agora);
};

// Cancelar fecha o card aberto (motivo "cancelou o seguro"); o card fica
// guardado para o "Voltar a ativo" reabrir.
export const cancelar = (id, agora = Date.now()) => {
  const { renovacao } = seguroPorId(id, agora);
  escrever(id, atual => ({
    campos: {
      ...atual.campos,
      canceladoEm: emSegundos(agora),
      renovacao: null,
      renovacaoFechada: renovacao,
    },
    feitos: feito(atual, 'cancelado', agora, {
      fechouCard: Boolean(renovacao),
    }),
  }));
  return seguroPorId(id, agora);
};

export const voltarAAtivo = (id, agora = Date.now()) => {
  const fechada = seguroPorId(id, agora).renovacaoFechada ?? null;
  escrever(id, atual => ({
    campos: {
      ...atual.campos,
      canceladoEm: null,
      renovacao: fechada ?? original(id, agora).renovacao,
      renovacaoFechada: null,
    },
    feitos: feito(atual, 'voltou_a_ativo', agora),
  }));
  return seguroPorId(id, agora);
};

// Guarda o PDF. `usar` são os campos em que vale o que está no PDF; os outros
// ficam como estão. No renovado, a apólice nova entra como ativa.
export const guardarPdf = (id, { usar = [] } = {}, agora = Date.now()) => {
  const seguro = seguroPorId(id, agora);
  const doPdf = oQueOPdfDiz(seguro, original(id, agora));
  const usados = Object.fromEntries(
    Object.entries(doPdf).filter(([campo]) => usar.includes(campo))
  );
  const daApoliceNova = seguro.renovadoEm
    ? { renovadoEm: null, renovacao: null, apoliceNova: true }
    : {};
  escrever(id, atual => ({
    antesDoPdf: atual,
    campos: {
      ...atual.campos,
      ...usados,
      ...daApoliceNova,
      temPdf: true,
      corrigidoAMao: seguro.corrigidoAMao.filter(campo => !(campo in usados)),
    },
    feitos: feito(
      atual,
      seguro.renovadoEm ? 'apolice_nova' : 'pdf_anexado',
      agora,
      { anterior: seguro.numero }
    ),
  }));
  return seguroPorId(id, agora);
};

export const desfazerPdf = (id, agora = Date.now()) => {
  const { antesDoPdf } = escritaDe(id);
  if (antesDoPdf) reporEscrita(id, antesDoPdf);
  return seguroPorId(id, agora);
};

export const cotar = (id, agora = Date.now()) => {
  const { renovacao } = seguroPorId(id, agora);
  escrever(id, atual => ({
    campos: { ...atual.campos, renovacao: { ...renovacao, cotando: true } },
    feitos: feito(atual, 'cotacao_pedida', agora),
  }));
  return seguroPorId(id, agora);
};

// ---- seguro de outra corretora (Tela 20) -------------------------------------

export const arquivosDaConversa = (pessoaId, agora = Date.now()) => ({
  pessoa: resumoDaPessoa(contexto(agora).gente.get(pessoaId)),
  arquivos: arquivosDeExemplo(),
});

// Guarda o lembrete: a pessoa não vira cliente; o seguro entra na ficha dela
// com o selo "Em outra corretora".
export const guardarDeFora = (
  pessoaId,
  { tipo, seguradora, termina },
  agora = Date.now()
) => {
  const id = PRIMEIRO_GUARDADO_DE_FORA + guardadosDeFora.length;
  guardadosDeFora = [
    ...guardadosDeFora,
    { id, pessoaId, tipo, seguradora, termina },
  ];
  return seguroPorId(id, agora);
};

export const desfazerDeFora = id => {
  guardadosDeFora = guardadosDeFora.filter(item => item.id !== id);
  return { id };
};

export const demoDaCarteira = {
  segurosDaCarteira,
  segurosComOsDeFora,
  seguroPorId,
  historiaDoSeguro,
  lerPdf,
  corrigir,
  cancelar,
  voltarAAtivo,
  guardarPdf,
  desfazerPdf,
  cotar,
  arquivosDaConversa,
  lerDeFora,
  guardarDeFora,
  desfazerDeFora,
};
