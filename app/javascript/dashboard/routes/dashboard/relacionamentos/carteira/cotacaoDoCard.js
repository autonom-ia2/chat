// #2897 — a cotação dentro da renovação de um seguro: em que estado ela está,
// um de cada vez, e se a renovação já terminou. Funções puras: devolvem o nome
// do estado; quem desenha traduz e põe o botão. A ordem importa: o que já saiu
// vem antes de tudo; depois, o que impede a proposta de chegar à pessoa.
import { DESFECHOS } from './situacaoDaRenovacao';

export const COTACAO = {
  ENVIADA_SOZINHA: 'ENVIADA_SOZINHA',
  ENVIADA_POR_VOCE: 'ENVIADA_POR_VOCE',
  ENVIADA_POR: 'ENVIADA_POR',
  SEM_TELEFONE: 'SEM_TELEFONE',
  NAO_QUER: 'NAO_QUER',
  PRECO_SEM_PDF: 'PRECO_SEM_PDF',
  PRONTA: 'PRONTA',
  PARCIAL: 'PARCIAL',
  COTANDO: 'COTANDO',
  AGGER_FORA: 'AGGER_FORA',
  DEMOROU: 'DEMOROU',
  FALHOU: 'FALHOU',
  FALTOU_PERGUNTADO: 'FALTOU_PERGUNTADO',
  FALTOU_SEM_AGENTE: 'FALTOU_SEM_AGENTE',
  NAO_COTA: 'NAO_COTA',
  NAO_COMECOU: 'NAO_COMECOU',
};

export const FIM = { RENOVOU: 'renovou', NAO_RENOVOU: 'nao_renovou' };
const ETAPA_RENOVADO = 'Renovado';

// Como a renovação terminou: '' enquanto ainda anda.
export const fimDaRenovacao = (renovacao = {}) => {
  if (renovacao?.desfecho === DESFECHOS.NAO_RENOVOU) return FIM.NAO_RENOVOU;
  return renovacao?.etapa === ETAPA_RENOVADO ? FIM.RENOVOU : '';
};

const PAROU = {
  agger_fora: COTACAO.AGGER_FORA,
  demorou: COTACAO.DEMOROU,
  falhou: COTACAO.FALHOU,
};

const enviada = proposta => {
  if (proposta.enviadaSozinha) return COTACAO.ENVIADA_SOZINHA;
  return proposta.enviadaPor?.papel
    ? COTACAO.ENVIADA_POR_VOCE
    : COTACAO.ENVIADA_POR;
};

// Antes de sair: o que a cotação já tem, do mais adiantado ao que nem começou.
const antesDeEnviar = (renovacao, cotaSozinha) => {
  const { proposta, respostas, cotando, parou, faltou, perguntou } = renovacao;
  if (proposta) return proposta.semPdf ? COTACAO.PRECO_SEM_PDF : COTACAO.PRONTA;
  if (respostas) return COTACAO.PARCIAL;
  if (cotando) return COTACAO.COTANDO;
  if (PAROU[parou]) return PAROU[parou];
  if (faltou) {
    return perguntou ? COTACAO.FALTOU_PERGUNTADO : COTACAO.FALTOU_SEM_AGENTE;
  }
  return cotaSozinha ? COTACAO.NAO_COMECOU : COTACAO.NAO_COTA;
};

// `null` quando não há cotação a mostrar (sem renovação, ou ela já terminou).
export const cotacaoDoCard = (seguro, { cotaSozinha = false } = {}) => {
  const { renovacao, pessoa } = seguro ?? {};
  if (!renovacao || fimDaRenovacao(renovacao)) return null;
  if (renovacao.proposta?.enviadaEm) return enviada(renovacao.proposta);
  if (!pessoa?.phone_number) return COTACAO.SEM_TELEFONE;
  if (pessoa.opted_out_at) return COTACAO.NAO_QUER;
  return antesDeEnviar(renovacao, cotaSozinha);
};

// A proposta que espera alguém apertar Enviar.
export const esperaEnvio = (seguro, opcoes) =>
  cotacaoDoCard(seguro, opcoes) === COTACAO.PRONTA;

// Quantas seguradoras já deram preço e quantas ainda não responderam.
export const contarRespostas = (respostas = []) => {
  const deram = respostas.filter(resposta => resposta.valor !== null).length;
  return { deram, faltam: respostas.length - deram };
};
