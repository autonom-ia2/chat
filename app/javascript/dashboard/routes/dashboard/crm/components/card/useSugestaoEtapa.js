import { computed, onBeforeUnmount, ref, watch } from 'vue';
import { useAlert } from 'dashboard/composables';
import CrmKanbanAPI from 'dashboard/api/crmKanban';

// #1423 — a sugestão de etapa do card (IA-01), com a mesma proteção contra
// resposta atrasada da gaveta antiga: a resposta só vale para o card e a
// rodada que a pediram. Depois de aceitar, avisa a gaveta para recarregar o
// card (a antiga não recarregava, OB-04).
export const useSugestaoEtapa = ({ t, cardId, inicial, ligada, aoMudar }) => {
  const sugestao = ref(null);
  const carregando = ref(false);
  const lendo = ref(false);
  const aviso = ref('');
  const respondendo = ref(false);
  let rodada = 0;

  const vale = (id, minha) => minha === rodada && id === cardId.value;

  const carregar = async () => {
    const id = cardId.value;
    const minha = rodada;
    carregando.value = true;
    try {
      const resposta = await CrmKanbanAPI.getCurrentAiSuggestion(id);
      if (vale(id, minha)) sugestao.value = resposta.data.payload;
    } catch {
      if (vale(id, minha)) sugestao.value = null;
    } finally {
      if (minha === rodada) carregando.value = false;
    }
  };

  const lerDeNovo = async () => {
    const id = cardId.value;
    if (!id || lendo.value) return;
    const minha = rodada;
    lendo.value = true;
    aviso.value = '';
    try {
      const resposta = await CrmKanbanAPI.evaluateCardAi(id);
      if (!vale(id, minha)) return;
      const dados = resposta.data.payload || {};
      if (['suggested', 'auto_moved'].includes(dados.status)) {
        sugestao.value = dados.suggestion || null;
        if (dados.status === 'auto_moved') {
          aviso.value = t('CRM_CARD.ETAPA.MOVEU_SOZINHO');
          aoMudar();
        }
      } else if (dados.status === 'below_threshold') {
        sugestao.value = null;
        aviso.value = t('CRM_CARD.ETAPA.SEM_CERTEZA');
      } else if (dados.error) {
        sugestao.value = null;
        aviso.value = t('CRM_CARD.ETAPA.PULOU', { motivo: dados.error });
      } else {
        sugestao.value = dados.suggestion || null;
        if (!sugestao.value) aviso.value = t('CRM_CARD.ETAPA.NADA_A_MUDAR');
      }
    } catch {
      if (vale(id, minha)) useAlert(t('CRM_KANBAN.AI_CARD.EVALUATE_ERROR'));
    } finally {
      if (minha === rodada) lendo.value = false;
    }
  };

  const responder = async (aceitar, alertaDeErro) => {
    const atual = sugestao.value;
    if (!atual?.id || respondendo.value) return;
    respondendo.value = true;
    try {
      if (aceitar) await CrmKanbanAPI.acceptAiSuggestion(atual.id);
      else await CrmKanbanAPI.dismissAiSuggestion(atual.id);
      sugestao.value = null;
      if (aceitar) {
        // F3: aceitar a sugestão de fechar encerra o card, não muda de etapa.
        useAlert(
          t(
            atual.fechar
              ? 'CRM_CARD.FECHAR_SUGESTAO.FECHOU'
              : 'CRM_KANBAN.AI_CARD.ACCEPT_SUCCESS'
          )
        );
        aoMudar();
      }
    } catch {
      useAlert(t(alertaDeErro));
    } finally {
      respondendo.value = false;
    }
  };
  const aceitar = () => responder(true, 'CRM_KANBAN.AI_CARD.ACCEPT_ERROR');
  const dispensar = () => responder(false, 'CRM_KANBAN.AI_CARD.DISMISS_ERROR');

  watch(
    () => [cardId.value, inicial.value, ligada.value],
    () => {
      rodada += 1;
      carregando.value = false;
      lendo.value = false;
      aviso.value = '';
      sugestao.value = inicial.value || null;
      if (ligada.value && cardId.value && !inicial.value) carregar();
    },
    { immediate: true }
  );
  onBeforeUnmount(() => {
    rodada += 1;
  });

  return {
    sugestao: computed(() => (sugestao.value?.id ? sugestao.value : null)),
    carregando,
    lendo,
    aviso,
    respondendo,
    lerDeNovo,
    aceitar,
    dispensar,
  };
};
