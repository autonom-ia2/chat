// #2894 — o prazo de 7 dias para desfazer uma lista trazida, e a data em
// palavras da casa ("18/11").
import { DIA_EM_MS } from '../fonte/grupos';

export const DIAS_PARA_DESFAZER = 7;

export const SITUACOES_DA_LISTA = {
  PRONTO: 'pronto',
  TRAZENDO: 'trazendo',
  DESFEITO: 'desfeito',
};

export const PRAZO = {
  ABERTO: 'aberto',
  ACABOU: 'acabou',
  NAO_SE_APLICA: 'nao_se_aplica',
};

export const prazoParaDesfazer = quandoMs =>
  quandoMs + DIAS_PARA_DESFAZER * DIA_EM_MS;

// Só lista pronta tem prazo. Trazendo ainda não dá para desfazer; desfeita já foi.
export const situacaoDoPrazo = (lista, agora) => {
  if (lista.situacao !== SITUACOES_DA_LISTA.PRONTO) return PRAZO.NAO_SE_APLICA;
  return agora <= prazoParaDesfazer(lista.quando) ? PRAZO.ABERTO : PRAZO.ACABOU;
};

export const formatarDia = (ms, locale = 'pt-BR') =>
  new Intl.DateTimeFormat(String(locale).replace('_', '-'), {
    day: '2-digit',
    month: '2-digit',
  }).format(new Date(ms));
