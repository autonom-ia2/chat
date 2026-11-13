// #2897 — o que a carteira fictícia soma à lista de pessoas da demonstração.
// Na conta de verdade quem faz isto é o servidor, dentro da consulta da lista
// (Carteira::NaListaDePessoas): o grupo "Só tem um seguro" e a busca pelo
// número da apólice e pelo bem segurado. Só é carregado no ambiente de
// desenvolvimento (fonte/listaFonte.js, `import.meta.env.DEV`).
import { segurosDaCarteira } from './carteira';
import { GRUPO_SO_UM_SEGURO } from '../fonte/grupos';
import { estaValendo } from '../fonte/selosDoSeguro';

const SEM_SEGURO = [];

// id da pessoa -> os seguros dela.
const porPessoa = seguros =>
  seguros.reduce(
    (mapa, seguro) =>
      new Map(mapa).set(seguro.pessoaId, [
        ...(mapa.get(seguro.pessoaId) ?? SEM_SEGURO),
        seguro,
      ]),
    new Map()
  );

// `grupos`: id do grupo -> quem pertence. `campos`: onde a busca também procura
// (com letra, no número e no bem; só com número, nos dígitos do número).
export const carteiraNaLista = (agora = Date.now()) => {
  const mapa = porPessoa(segurosDaCarteira(agora));
  const de = pessoa => mapa.get(pessoa.id) ?? SEM_SEGURO;
  return {
    grupos: {
      // Cancelado e vencido não contam.
      [GRUPO_SO_UM_SEGURO]: pessoa =>
        de(pessoa).filter(seguro => estaValendo(seguro, agora)).length === 1,
    },
    campos: pessoa => ({
      textos: de(pessoa).flatMap(seguro => [seguro.numero, seguro.bem]),
      numeros: de(pessoa).map(seguro => seguro.numero),
    }),
  };
};
