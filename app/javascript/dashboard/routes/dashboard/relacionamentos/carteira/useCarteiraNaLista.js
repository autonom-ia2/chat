// #2897 — o selo de seguro na lista de pessoas, na conta que tem a carteira de
// seguros: ao lado do nome, o selo do seguro que mais pede atenção (o vencido,
// depois o ativo que termina antes, o cancelado por último).
//
// `comSelos(fonte)` devolve a fonte da lista com um passo a mais: cada página
// de pessoas que chega dispara um pedido só, com os ids daquela página, e o
// que volta fica em `daPessoa(id)`. A lista não espera por ele: as pessoas
// aparecem e o selo entra quando chegar. Reler a lista relê os selos.
//
// A carteira fora do ar não derruba a lista: as pessoas aparecem sem o selo, e
// é a aba Seguros que mostra o erro. Na conta sem a carteira (`ligada` falso)
// nada disto acontece: nenhum pedido sai e a fonte da carteira nem é baixada.
//
// O grupo "Só tem um seguro" e a busca pelo número da apólice e pelo bem não
// passam por aqui: vão no próprio pedido da lista (fonte/grupos.js e, no
// servidor, Carteira::NaListaDePessoas).
import { shallowRef } from 'vue';
import { ABAS } from '../fonte/grupos';

const CARREGAR_FONTE = () => import('../fonte/carteiraFonte');

// `ligada`: a conta tem a carteira (o `computed` de useContaDeSeguros).
export const useCarteiraNaLista = ({
  demo = null,
  ligada,
  carregarFonte = CARREGAR_FONTE,
}) => {
  // id da pessoa -> { quantos, selo, tipo, dias }, ou nulo para quem não tem
  // seguro.
  const resumos = shallowRef({});

  // Quem não veio na resposta não tem (mais) seguro: o selo antigo sai.
  const lerOsDe = async ids => {
    try {
      const { carteiraFonte } = await carregarFonte();
      const chegaram = await carteiraFonte({ demo }).resumoPorPessoa(ids);
      resumos.value = {
        ...resumos.value,
        ...Object.fromEntries(ids.map(id => [id, chegaram[id] ?? null])),
      };
    } catch {
      // De propósito: sem a carteira a lista segue inteira, só sem os selos.
    }
  };

  const comSelos = daLista => ({
    ...daLista,
    async listar(pedido = {}) {
      const resposta = await daLista.listar(pedido);
      const ids = resposta.itens.map(({ id }) => id);
      if (ligada.value && pedido.aba !== ABAS.EMPRESAS && ids.length) {
        lerOsDe(ids);
      }
      return resposta;
    },
  });

  return {
    comSelos,
    daPessoa: id => resumos.value[id] ?? null,
  };
};
