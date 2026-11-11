// #2897 — o que se faz no card da renovação, na demonstração: enviar a
// proposta, marcar "Renovou" ou "Não renovou" (com desfazer), cotar com o dado
// que faltava, pedir o PDF de novo, pedir a proposta de uma seguradora e o
// texto em palavras simples. Só é carregado no ambiente de desenvolvimento.
// Como as outras escritas da carteira (demo/carteira.js), tudo fica na memória
// e cada ação devolve o seguro novo.
import {
  emSegundos,
  escrever,
  escritaDe,
  feito,
  reporEscrita,
  seguroPorId,
} from './carteira';
import { DESFECHOS } from '../carteira/situacaoDaRenovacao';

const VOCE = { papel: 'voce' };
const MOTIVO_ESCRITO = 'outro';
const AUMENTO_DA_PROPOSTA_ANEXADA = 5;
const CENTAVOS = 100;

// Seguradoras inventadas que respondem (ou não) a uma cotação: quanto cada uma
// pede em relação ao valor de hoje. Uma delas não dá proposta em PDF.
const RESPOSTAS_DA_COTACAO = [
  { nome: 'Seguradora Atlântica', aumento: 5 },
  { nome: 'Serra Azul Seguros', aumento: 9 },
  { nome: 'Seguradora Vale Verde', aumento: 15, semPdf: true },
  { nome: 'Horizonte Seguros' },
  { nome: 'Seguradora Ponte Nova' },
];

const comAumento = (valor, aumento) =>
  Math.round(valor * (CENTAVOS + aumento)) / CENTAVOS;

const respostasPara = seguro =>
  RESPOSTAS_DA_COTACAO.map(({ nome, aumento, semPdf = false }) => ({
    nome,
    semPdf,
    variacao: aumento ?? null,
    valor: aumento ? comAumento(seguro.valor, aumento) : null,
  }));

const propostaDeExemplo = seguro => ({
  seguradora: seguro.seguradora,
  valor: comAumento(seguro.valor, AUMENTO_DA_PROPOSTA_ANEXADA),
  variacao: AUMENTO_DA_PROPOSTA_ANEXADA,
});

// `?caso=`: o card cai num estado que o exemplo de sempre não mostra. Só vale
// enquanto a renovação não tem proposta nem cotação em andamento: depois que a
// pessoa age (cotar de novo, pedir a proposta), vale o que ela fez.
const CASOS = {
  cotacao_parcial: seguro => ({ respostas: respostasPara(seguro) }),
  cotacao_sem_pdf: seguro => ({
    proposta: { ...propostaDeExemplo(seguro), semPdf: true },
  }),
  cotacao_agger_fora: () => ({ parou: 'agger_fora' }),
  cotacao_demorou: () => ({ parou: 'demorou' }),
  cotacao_falhou: () => ({ parou: 'falhou' }),
  // Conta sem quem atenda sozinho: ninguém perguntou o dado que faltou.
  cotacao_sem_agente: () => ({ perguntou: null }),
};

export const comOCaso = (seguro, caso) => {
  const { renovacao } = seguro ?? {};
  const mexida = Boolean(escritaDe(seguro?.id).campos.renovacao);
  if (!CASOS[caso] || !renovacao || mexida) return seguro;
  if (renovacao.proposta || renovacao.cotando || renovacao.desfecho) {
    return seguro;
  }
  return { ...seguro, renovacao: { ...renovacao, ...CASOS[caso](seguro) } };
};

// ---- escritas ---------------------------------------------------------------

// Muda a renovação do seguro e registra o que foi feito na história.
const naRenovacao = (id, agora, tipo, mudar, valores = {}, outros = {}) => {
  const seguro = seguroPorId(id, agora);
  escrever(id, atual => ({
    campos: {
      ...atual.campos,
      ...outros,
      renovacao: { ...seguro.renovacao, ...mudar(seguro) },
    },
    feitos: feito(atual, tipo, agora, valores),
  }));
  return seguroPorId(id, agora);
};

export const enviarProposta = (id, _dados, agora = Date.now()) =>
  naRenovacao(id, agora, 'proposta_enviada', ({ renovacao }) => ({
    etapa: 'Opções enviadas',
    proposta: {
      ...renovacao.proposta,
      enviadaPor: VOCE,
      enviadaEm: emSegundos(agora),
    },
  }));

// "Renovou" e "Não renovou" guardam como estava antes, para o Desfazer.
const comDesfecho = (id, agora, fechar) => {
  const antes = escritaDe(id);
  const seguro = fechar();
  escrever(id, atual => ({ ...atual, antesDoDesfecho: antes }));
  return seguro;
};

export const renovou = (id, _dados, agora = Date.now()) =>
  comDesfecho(id, agora, () =>
    naRenovacao(
      id,
      agora,
      'renovou',
      () => ({ etapa: 'Renovado', cotando: false }),
      {},
      { renovadoEm: emSegundos(agora) }
    )
  );

// O seguro continua com o selo de agora e vira Vencido quando terminar.
// O motivo escrito à mão vai à história com as palavras de quem escreveu.
export const naoRenovou = (id, { motivo, texto = '' }, agora = Date.now()) => {
  const escrito = motivo === MOTIVO_ESCRITO;
  return comDesfecho(id, agora, () =>
    naRenovacao(
      id,
      agora,
      escrito ? 'nao_renovou_outro' : 'nao_renovou',
      () => ({ desfecho: DESFECHOS.NAO_RENOVOU, cotando: false }),
      escrito ? { texto } : { motivo },
      { motivo, motivoEscrito: texto }
    )
  );
};

export const desfazerDesfecho = (id, _dados, agora = Date.now()) => {
  const { antesDoDesfecho } = escritaDe(id);
  if (antesDoDesfecho) reporEscrita(id, antesDoDesfecho);
  return seguroPorId(id, agora);
};

export const cotarComDado = (id, _dados, agora = Date.now()) =>
  naRenovacao(id, agora, 'cotacao_pedida', () => ({
    faltou: null,
    cotando: true,
  }));

export const pedirPdf = (id, _dados, agora = Date.now()) =>
  naRenovacao(id, agora, 'pdf_pedido', seguro => ({
    proposta: {
      ...(seguro.renovacao.proposta ?? propostaDeExemplo(seguro)),
      semPdf: false,
    },
  }));

// A proposta oficial da seguradora escolhida entre as que já deram preço.
export const pedirProposta = (id, { seguradora }, agora = Date.now()) =>
  naRenovacao(
    id,
    agora,
    'proposta_pedida',
    seguro => {
      const { valor, variacao } = respostasPara(seguro).find(
        resposta => resposta.nome === seguradora
      );
      return {
        respostas: null,
        proposta: { seguradora, valor, variacao, oficial: true },
      };
    },
    { seguradora }
  );

// Conta que não cota sozinha: a equipe cota por fora e põe a proposta no card.
export const anexarProposta = (id, _dados, agora = Date.now()) =>
  naRenovacao(id, agora, 'proposta_anexada', seguro => ({
    proposta: { ...propostaDeExemplo(seguro), oficial: true },
  }));

// ---- seu seguro em palavras simples (Tela 19) --------------------------------

const nasPalavras = (id, agora, mudanca, tipo) => {
  const { palavras } = seguroPorId(id, agora);
  escrever(id, atual => ({
    campos: { ...atual.campos, palavras: { ...palavras, ...mudanca } },
    feitos: tipo ? feito(atual, tipo, agora) : atual.feitos,
  }));
  return seguroPorId(id, agora);
};

export const salvarPalavras = (id, { texto }, agora = Date.now()) =>
  nasPalavras(id, agora, { texto });

export const enviarPalavras = (id, _dados, agora = Date.now()) =>
  nasPalavras(id, agora, { enviadoEm: emSegundos(agora) }, 'palavras_enviadas');

export const demoDaRenovacao = {
  comOCaso,
  enviarProposta,
  renovou,
  naoRenovou,
  desfazerDesfecho,
  cotarComDado,
  pedirPdf,
  pedirProposta,
  anexarProposta,
  salvarPalavras,
  enviarPalavras,
};
