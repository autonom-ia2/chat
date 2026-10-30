import { computed, onBeforeUnmount, ref } from 'vue';
import CrmKanbanAPI from 'dashboard/api/crmKanban';
import { contagemDoResumo } from './grupos';
import {
  POR_PAGINA,
  parametrosDaContagem,
  parametrosDaLista,
} from './parametros';

// #2283 — os dados da Lista nova: a página de cards (sort=acao), "Mostrar
// mais" e a contagem dos grupos (summaries?group_by=acao). Tempo real sem
// pular linha: o card que já está na tela muda no lugar (o grupo fica o que
// era até "Atualizar"); o que não está soma na faixa "Chegaram N novidades.".
// Só a contagem recarrega sozinha.
const REALTIME_ACTION = 'crmKanban/handleRealtimeCardEvent';
const ESPERA_DA_CONTAGEM = 600;

export const useListaAcaoDados = ({ store, estado }) => {
  const cards = ref([]);
  const total = ref(0);
  const contagem = ref({});
  const pagina = ref(1);
  const carregando = ref(false);
  const erro = ref(false);
  const novidades = ref(0);
  let pedido = 0;
  // Linhas que a própria pessoa tirou ("Feito"): o eco do tempo real não é
  // novidade.
  const tiradas = new Set();

  const temMais = computed(() => cards.value.length < total.value);

  const atualizarContagem = async () => {
    const atual = pedido;
    try {
      const resposta = await CrmKanbanAPI.cardsGroupSummary(
        parametrosDaContagem(estado())
      );
      if (atual === pedido)
        contagem.value = contagemDoResumo(resposta.data?.payload);
    } catch {
      // A contagem que já está na tela fica; a lista segue funcionando.
    }
  };

  const buscarPagina = async numero => {
    const resposta = await CrmKanbanAPI.getCards({
      ...parametrosDaLista(estado()),
      page: numero,
      per_page: POR_PAGINA,
    });
    return {
      linhas: resposta.data?.payload || [],
      contados: resposta.data?.meta?.count || 0,
    };
  };

  const carregar = async () => {
    if (!estado().pipelineId) return;
    pedido += 1;
    const atual = pedido;
    carregando.value = true;
    erro.value = false;
    try {
      const [{ linhas, contados }] = await Promise.all([
        buscarPagina(1),
        atualizarContagem(),
      ]);
      if (atual !== pedido) return;
      cards.value = linhas;
      total.value = contados;
      pagina.value = 1;
      novidades.value = 0;
      tiradas.clear();
    } catch {
      if (atual === pedido) erro.value = true;
    } finally {
      if (atual === pedido) carregando.value = false;
    }
  };

  const mostrarMais = async () => {
    if (!temMais.value || carregando.value) return;
    const atual = pedido;
    carregando.value = true;
    try {
      const { linhas, contados } = await buscarPagina(pagina.value + 1);
      if (atual !== pedido) return;
      const jaTem = new Set(cards.value.map(card => card.id));
      cards.value = [
        ...cards.value,
        ...linhas.filter(card => !jaTem.has(card.id)),
      ];
      total.value = contados;
      pagina.value += 1;
    } catch {
      erro.value = true;
    } finally {
      if (atual === pedido) carregando.value = false;
    }
  };

  // Troca uma linha no lugar, sem mudar de grupo nem de posição.
  const trocarLinha = (id, mudancas) => {
    cards.value = cards.value.map(card =>
      card.id === id ? { ...card, ...mudancas } : card
    );
  };
  const tirarLinha = id => {
    tiradas.add(id);
    cards.value = cards.value.filter(card => card.id !== id);
    total.value = Math.max(0, total.value - 1);
  };

  let relogioDaContagem = null;
  const contarDepois = () => {
    clearTimeout(relogioDaContagem);
    relogioDaContagem = setTimeout(atualizarContagem, ESPERA_DA_CONTAGEM);
  };

  const aoTempoReal = ({ card }) => {
    if (!card?.id || String(card.pipeline_id) !== String(estado().pipelineId))
      return;
    const naTela = cards.value.find(item => item.id === card.id);
    if (naTela) {
      // O grupo da linha é o da última carga (o tempo real não traz o grupo).
      trocarLinha(card.id, { ...card, action_group: naTela.action_group });
    } else if (!tiradas.has(card.id)) {
      novidades.value += 1;
    }
    contarDepois();
  };

  const parar = store.subscribeAction({
    after: action => {
      if (action.type === REALTIME_ACTION) aoTempoReal(action.payload || {});
    },
  });
  onBeforeUnmount(() => {
    parar();
    clearTimeout(relogioDaContagem);
  });

  return {
    cards,
    total,
    contagem,
    carregando,
    erro,
    novidades,
    temMais,
    carregar,
    mostrarMais,
    atualizarContagem,
    trocarLinha,
    tirarLinha,
  };
};
