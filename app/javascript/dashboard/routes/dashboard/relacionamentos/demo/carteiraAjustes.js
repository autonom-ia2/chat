// #2898 — os ajustes das renovações na demonstração: o que a conta fictícia
// escolheu e os funis que ela tem. Só é carregado no ambiente de
// desenvolvimento. O que é salvo fica na memória deste módulo e
// some ao recarregar a página.
import { AJUSTES_PADRAO } from '../carteira/ajustesDaRenovacao';

// Funis e etapas inventados, de uma conta qualquer.
export const FUNIS_DA_DEMO = [
  {
    id: 1,
    nome: 'Renovação',
    etapas: [
      { id: 11, nome: 'A vencer' },
      { id: 12, nome: 'Em conversa' },
      { id: 13, nome: 'Proposta enviada' },
    ],
  },
  {
    id: 2,
    nome: 'Vendas',
    etapas: [
      { id: 21, nome: 'Novo contato' },
      { id: 22, nome: 'Em conversa' },
      { id: 23, nome: 'Proposta' },
    ],
  },
];
// A conta cheia já escolheu onde ficam as renovações.
const ESCOLHA_DA_DEMO = Object.freeze({
  ...AJUSTES_PADRAO,
  funilId: 1,
  etapaId: 11,
});

let guardados = null;

export const esquecerAjustesDaDemo = () => {
  guardados = null;
};

// `semEscolha`: a conta que ainda não escolheu o funil (a que não tem seguros).
export const ajustesDaDemo = (semEscolha = false) =>
  guardados ?? (semEscolha ? AJUSTES_PADRAO : ESCOLHA_DA_DEMO);

// Alguém já salvou os ajustes nesta visita: a escolha que vale é a salva.
export const salvouNaDemo = () => guardados !== null;

export const salvarAjustesNaDemo = novos => {
  guardados = { ...novos };
  return guardados;
};
