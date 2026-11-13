// #2897 — o selo de seguro na lista de pessoas, na conta que tem a carteira de
// seguros: ao lado do nome, o selo do seguro que mais pede atenção (o vencido,
// depois o que está em renovação, o renovado, o ativo que termina antes e o
// cancelado por último).
//
// `comSelos(fonte)` devolve a fonte da lista com um passo a mais: cada página
// de pessoas que chega dispara um pedido só, com os ids daquela página, e o
// que volta fica em `daPessoa(id)`. A lista não espera por ele: as pessoas
// aparecem e o selo entra quando chegar. Reler a lista relê os selos.
//
// A carteira fora do ar não derruba a lista: as pessoas aparecem sem o selo.
// Mas pessoa sem selo se lê como "não tem seguro": por isso `falhou` liga, a
// tela avisa acima das linhas, e `tentarDeNovo` relê só os selos que faltaram
// (a lista não é relida). Só por clique: nada aqui tenta sozinho. A falha
// também vai ao registro de erros do painel, sem dado de pessoa nem de seguro
// (só o nome do erro e a pilha). Na conta sem a carteira (`ligada` falso) nada
// disto acontece: nenhum pedido sai e a fonte da carteira nem é baixada.
//
// Cada leitura da página 1 abre uma consulta nova (outro grupo, outra busca,
// outro filtro, ou a mesma relida). Selo pedido numa consulta antiga que chega
// atrasado é descartado, e o selo de quem saiu da tela sai junto quando os da
// consulta nova chegam: fica guardado só o de quem está à vista.
//
// O grupo "Só tem um seguro" e a busca pelo número da apólice e pelo bem não
// passam por aqui: vão no próprio pedido da lista (fonte/grupos.js e, no
// servidor, Carteira::NaListaDePessoas).
import { ref, shallowRef } from 'vue';
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
  // Faltou o selo de alguém que está à vista; e a releitura pedida pelo clique
  // está em andamento.
  const falhou = ref(false);
  const tentando = ref(false);
  // A consulta que está na tela, os ids das pessoas que ela já mostrou e as
  // páginas dela (os ids de cada uma) cujo selo não chegou.
  let consulta = 0;
  let aVista = [];
  let semSelo = [];

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
      // De propósito: sem a carteira a lista segue inteira, só sem os selos.
      // Mas a falha fica registrada, e a tela avisa.
      reportarSemDados(falha, ONDE_FALHOU);
      if (minha === consulta) semSelo = [...semSelo, ids];
    }
  };

  // O aviso acompanha o que falta: some quando o selo de todos à vista chegou.
  // Durante a releitura pedida pelo clique ele fica, e quem decide é ela.
  const lerEAvisar = async (ids, minha) => {
    await lerOsDe(ids, minha);
    if (minha === consulta && !tentando.value) {
      falhou.value = semSelo.length > 0;
    }
  };

  const tentarDeNovo = async () => {
    if (tentando.value) return;
    const paginas = semSelo;
    const minha = consulta;
    semSelo = [];
    tentando.value = true;
    await Promise.all(paginas.map(ids => lerOsDe(ids, minha)));
    tentando.value = false;
    falhou.value = semSelo.length > 0;
  };

  const aoChegar = (pedido, resposta, primeira, minha) => {
    const pede = ligada.value && pedido.aba !== ABAS.EMPRESAS;
    const ids = pede ? resposta.itens.map(({ id }) => id) : [];
    aVista = [...aVista, ...ids];
    if (ids.length) {
      lerEAvisar(ids, minha);
      return;
    }
    if (!primeira) return;
    // Página 1 sem ninguém para pedir (lista vazia, aba Empresas): nenhum selo
    // chega para tirar os antigos, e não há selo faltando para avisar.
    falhou.value = false;
    if (Object.keys(resumos.value).length) resumos.value = {};
  };

  const comSelos = daLista => ({
    ...daLista,
    async listar(pedido = {}) {
      const primeira = (pedido.pagina ?? PRIMEIRA_PAGINA) === PRIMEIRA_PAGINA;
      if (primeira) {
        consulta += 1;
        aVista = [];
        semSelo = [];
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
    falhou,
    tentando,
    tentarDeNovo,
  };
};
