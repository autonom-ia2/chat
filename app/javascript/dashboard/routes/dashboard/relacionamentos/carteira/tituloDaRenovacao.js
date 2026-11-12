// #2897 — o título da gaveta da renovação: em que pé ela está, sem contradizer
// o bloco "Cotação" logo abaixo. Função pura (a etapa e o estado da cotação):
// devolve o nome da frase; quem desenha traduz. Antes de as opções saírem,
// quando a cotação já andou ou parou, quem fala é ela; no resto vale a situação
// de sempre (situacaoDaRenovacao.js).
import { COTACAO, aguardaRespostas, contarRespostas } from './cotacaoDoCard';
import {
  antesDeAsOpcoesSairem,
  situacaoDaRenovacao,
} from './situacaoDaRenovacao';

const PELA_COTACAO = {
  [COTACAO.PARCIAL]: 'PRECOS_CHEGANDO',
  [COTACAO.FALTOU_PERGUNTADO]: 'FALTAM_DADOS',
  [COTACAO.FALTOU_SEM_AGENTE]: 'FALTAM_DADOS',
  [COTACAO.AGGER_FORA]: 'COTACAO_PAROU',
  [COTACAO.DEMOROU]: 'COTACAO_PAROU',
  [COTACAO.FALHOU]: 'COTACAO_PAROU',
  [COTACAO.NAO_COTA]: 'FALTA_A_COTACAO',
  [COTACAO.SEM_TELEFONE]: 'PRONTA_FALTA_O_TELEFONE',
  [COTACAO.NAO_QUER]: 'PRONTA_ENVIE_NA_CONVERSA',
  [COTACAO.BLOQUEADO]: 'PRONTA_ENVIE_NA_CONVERSA',
  [COTACAO.NAO_SAIU]: 'PRONTA_NAO_SAIU',
  [COTACAO.PRECO_SEM_PDF]: 'PRECO_SEM_PDF',
};

// Um dado só faltando tem a frase dele ("Falta um dado para cotar.").
const UM_SO = { FALTAM_DADOS: 'FALTA_UM_DADO' };
const noNumeroCerto = (id, renovacao) =>
  (renovacao.faltou?.length ?? 1) > 1 ? id : (UM_SO[id] ?? id);

// Os preços "estão chegando" enquanto alguma seguradora ainda pode responder.
// Quando não sobra ninguém (todas responderam, recusaram, ficaram sem senha ou
// passaram do prazo), eles "chegaram". Se não sobra ninguém e nenhuma deu
// preço, não chegou nada: a cotação parou.
const comOsPrecos = (id, renovacao) => {
  if (id !== 'PRECOS_CHEGANDO' || aguardaRespostas(renovacao)) return id;
  return contarRespostas(renovacao.respostas).deram > 0
    ? 'PRECOS_CHEGARAM'
    : 'COTACAO_PAROU';
};

// `cotacao` é o estado que `cotacaoDoCard` devolve (ou null, sem cotação).
export const tituloDaRenovacao = (renovacao, cotacao) => {
  const pelaCotacao = antesDeAsOpcoesSairem(renovacao)
    ? PELA_COTACAO[cotacao]
    : null;
  return pelaCotacao
    ? { id: comOsPrecos(noNumeroCerto(pelaCotacao, renovacao), renovacao) }
    : situacaoDaRenovacao(renovacao);
};
