// #2897 — o título da gaveta da renovação: em que pé ela está, sem contradizer
// o bloco "Cotação" logo abaixo. Função pura (a etapa e o estado da cotação):
// devolve o nome da frase; quem desenha traduz. Antes de as opções saírem,
// quando a cotação já andou ou parou, quem fala é ela; no resto vale a situação
// de sempre (situacaoDaRenovacao.js).
import { COTACAO } from './cotacaoDoCard';
import {
  antesDeAsOpcoesSairem,
  situacaoDaRenovacao,
} from './situacaoDaRenovacao';

const PELA_COTACAO = {
  [COTACAO.PARCIAL]: 'PRECOS_CHEGANDO',
  [COTACAO.FALTOU_PERGUNTADO]: 'FALTA_UM_DADO',
  [COTACAO.FALTOU_SEM_AGENTE]: 'FALTA_UM_DADO',
  [COTACAO.AGGER_FORA]: 'COTACAO_PAROU',
  [COTACAO.DEMOROU]: 'COTACAO_PAROU',
  [COTACAO.FALHOU]: 'COTACAO_PAROU',
  [COTACAO.NAO_COTA]: 'FALTA_A_COTACAO',
  [COTACAO.SEM_TELEFONE]: 'PRONTA_FALTA_O_TELEFONE',
  [COTACAO.NAO_QUER]: 'PRONTA_ENVIE_NA_CONVERSA',
  [COTACAO.PRECO_SEM_PDF]: 'PRECO_SEM_PDF',
};

// `cotacao` é o estado que `cotacaoDoCard` devolve (ou null, sem cotação).
export const tituloDaRenovacao = (renovacao, cotacao) => {
  const pelaCotacao = antesDeAsOpcoesSairem(renovacao)
    ? PELA_COTACAO[cotacao]
    : null;
  return pelaCotacao ? { id: pelaCotacao } : situacaoDaRenovacao(renovacao);
};
