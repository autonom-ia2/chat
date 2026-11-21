import { GRUPOS_DE_COMPRA_IDS } from '../fonte/gruposDeCompra';

// #3097 — a frase do herói na visão por compra, pela ordem do que pede ação:
// quem passou da hora de voltar, depois quem está sem comprar há algum tempo,
// depois os campeões, depois quantos já compraram; sem nenhuma compra, diz de
// onde ela vem. Função pura: recebe `resumo.compras` do servidor
//   { passou_da_hora, em_risco, campeoes, compraram }: { pessoas, por_moeda }
// e devolve a chave da frase, o número, o valor (por moeda) e o grupo para
// onde o botão leva. Quem desenha traduz.
const { PASSOU_DA_HORA, EM_RISCO, CAMPEOES } = GRUPOS_DE_COMPRA_IDS;

const ORDEM = [
  {
    chave: 'passou_da_hora',
    frase: 'PASSOU',
    grupo: PASSOU_DA_HORA,
    botao: 'VER_QUEM_CHAMAR',
  },
  {
    chave: 'em_risco',
    frase: 'EM_RISCO',
    grupo: EM_RISCO,
    botao: 'VER_QUEM_CHAMAR',
  },
  {
    chave: 'campeoes',
    frase: 'CAMPEOES',
    grupo: CAMPEOES,
    botao: 'VER_CAMPEOES',
  },
  { chave: 'compraram', frase: 'COMPRARAM', grupo: null, botao: null },
];

export const escolherFraseDeCompras = (compras = {}) => {
  const achada = ORDEM.find(({ chave }) => (compras[chave]?.pessoas ?? 0) > 0);
  if (!achada)
    return {
      id: 'nenhuma',
      frase: 'NENHUMA',
      count: 0,
      porMoeda: [],
      grupo: null,
      botao: null,
    };
  const { pessoas, por_moeda: porMoeda = [] } = compras[achada.chave];
  return {
    id: achada.chave,
    frase: achada.frase,
    count: pessoas,
    porMoeda,
    grupo: achada.grupo,
    botao: achada.botao,
  };
};
