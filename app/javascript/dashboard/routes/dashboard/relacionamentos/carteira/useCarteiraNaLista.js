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
// é a aba Seguros que mostra o erro. A falha não some: vai ao registro de erros
// do painel, sem dado de pessoa nem de seguro (só o nome do erro e a pilha).
// Na conta sem a carteira (`ligada` falso) nada disto acontece: nenhum pedido
// sai e a fonte da carteira nem é baixada.
//
// Cada leitura da página 1 abre uma consulta nova (outro grupo, outra busca,
// outro filtro, ou a mesma relida). Selo pedido numa consulta antiga que chega
// atrasado é descartado, e o selo de quem saiu da tela sai junto quando os da
// consulta nova chegam: fica guardado só o de quem está à vista.
//
// O grupo "Só tem um seguro" e a busca pelo número da apólice e pelo bem não
// passam por aqui: vão no próprio pedido da lista (fonte/grupos.js e, no
// servidor, Carteira::NaListaDePessoas).
import { shallowRef } from 'vue';
import { reportarSemDados } from 'dashboard/helper/sentryPrivacy';
import { ABAS } from '../fonte/grupos';

const CARREGAR_FONTE = () => import('../fonte/carteiraFonte');
const PRIMEIRA_PAGINA = 1;
const ONDE_FALHOU = { tela: 'relacionamentos_lista_selos' };

// `ligada`: a conta tem a carteira (o `computed` de useContaDeSeguros).
export const useCarteiraNaLista = ({
  demo = null,
  ligada,
  carregarFonte = CARREGAR_FONTE,
}) => {
  // id da pessoa -> { quantos, selo, tipo, dias }, ou nulo para quem não tem
  // seguro.
  const resumos = shallowRef({});
  // A consulta que está na tela e os ids das pessoas que ela já mostrou.
  let consulta = 0;
  let aVista = [];

  // Quem não veio na resposta não tem (mais) seguro: o selo antigo sai. De
  // quem não está mais à vista, também.
  const guardar = (ids, chegaram) => {
    const juntos = {
      ...resumos.value,
      ...Object.fromEntries(ids.map(id => [id, chegaram[id] ?? null])),
    };
    resumos.value = Object.fromEntries(
      aVista.filter(id => id in juntos).map(id => [id, juntos[id]])
    );
  };

  const lerOsDe = async (ids, minha) => {
    try {
      const { carteiraFonte } = await carregarFonte();
      const chegaram = await carteiraFonte({ demo }).resumoPorPessoa(ids);
      if (minha === consulta) guardar(ids, chegaram);
    } catch (falha) {
      // Sem a carteira a lista segue inteira, só sem os selos.
      reportarSemDados(falha, ONDE_FALHOU);
    }
  };

  const aoChegar = (pedido, resposta, primeira, minha) => {
    const pede = ligada.value && pedido.aba !== ABAS.EMPRESAS;
    const ids = pede ? resposta.itens.map(({ id }) => id) : [];
    aVista = [...aVista, ...ids];
    if (ids.length) {
      lerOsDe(ids, minha);
      return;
    }
    // Página 1 sem ninguém para pedir (lista vazia, aba Empresas): nenhum selo
    // chega para tirar os antigos.
    if (primeira && Object.keys(resumos.value).length) resumos.value = {};
  };

  const comSelos = daLista => ({
    ...daLista,
    async listar(pedido = {}) {
      const primeira = (pedido.pagina ?? PRIMEIRA_PAGINA) === PRIMEIRA_PAGINA;
      if (primeira) {
        consulta += 1;
        aVista = [];
      }
      const minha = consulta;
      const resposta = await daLista.listar(pedido);
      if (minha === consulta) aoChegar(pedido, resposta, primeira, minha);
      return resposta;
    },
  });

  return {
    comSelos,
    daPessoa: id => resumos.value[id] ?? null,
  };
};
