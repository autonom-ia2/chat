import { computed, onBeforeUnmount, ref, watch } from 'vue';
import CrmKanbanAPI from 'dashboard/api/crmKanban';

// #1423 — "Em resumo" da conversa (IA-02), com a regra do
// gaveta antiga: começa pelo resumo que veio no detalhe do card (o
// servidor tira quando a pessoa não pode ver a conversa) e só pede um novo
// quando a pessoa abre "Conversas", o detalhe já chegou, há conversa e não há
// resumo. "Atualizar" pede de novo. Resposta atrasada de outro card é jogada fora.
export const useResumoConversa = ({ card, detalhe, ligada, aberta }) => {
  const resumo = ref(null);
  const carregando = ref(false);
  const erro = ref(false);
  let rodada = 0;

  const cardId = computed(() => card.value?.id || null);
  const temConversa = computed(() =>
    Boolean(card.value?.conversation_id || card.value?.conversation?.id)
  );
  const texto = computed(() => resumo.value?.text || '');
  const quando = computed(() => resumo.value?.generated_at || '');

  const gerar = async () => {
    const id = cardId.value;
    if (!id || carregando.value) return;
    rodada += 1;
    const minha = rodada;
    carregando.value = true;
    erro.value = false;
    try {
      const resposta = await CrmKanbanAPI.summarizeCardConversation(id);
      if (minha !== rodada || id !== cardId.value) return;
      const novo = resposta.data.payload?.ai_summary;
      if (novo?.text) resumo.value = novo;
      else erro.value = true;
    } catch {
      if (minha === rodada && id === cardId.value) erro.value = true;
    } finally {
      if (minha === rodada) carregando.value = false;
    }
  };

  watch(
    () => [cardId.value, card.value?.ai_summary],
    () => {
      rodada += 1;
      carregando.value = false;
      erro.value = false;
      resumo.value = card.value?.ai_summary || null;
    },
    { immediate: true }
  );
  watch(
    () => [aberta.value, detalhe.value, cardId.value],
    () => {
      if (
        ligada.value &&
        aberta.value &&
        detalhe.value &&
        temConversa.value &&
        !texto.value &&
        !carregando.value &&
        !erro.value
      )
        gerar();
    },
    { immediate: true }
  );
  onBeforeUnmount(() => {
    rodada += 1;
  });

  return { texto, quando, carregando, erro, gerar, temConversa };
};
