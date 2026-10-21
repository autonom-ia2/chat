<script setup>
// #2067: "Devolver para <agente>", numa linha calma acima da barra de escrever (como o aviso
// do WhatsApp API: no fluxo da caixa de resposta, sem fundo próprio, nunca por cima da
// conversa). Só quando a conversa está com uma pessoa e veio de um agente de IA; quem diz de
// qual é o servidor (meta.veio_da_ia, do registro de passagens). Devolver usa a atribuição
// de robô de hoje (POST assignments, assignee_type AgentBot).
import { computed, ref } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import ConversationApi from 'dashboard/api/inbox/conversation';
import { useAlert } from 'dashboard/composables';

const props = defineProps({
  conversation: { type: Object, required: true },
});

const store = useStore();
const { t } = useI18n();
const devolvendo = ref(false);

const ia = computed(() => props.conversation?.meta?.veio_da_ia || null);
const visivel = computed(
  () =>
    props.conversation?.meta?.assignee_type === 'User' &&
    Boolean(props.conversation?.meta?.assignee) &&
    Boolean(ia.value?.id)
);

const devolver = async () => {
  if (devolvendo.value) return;
  devolvendo.value = true;
  const conversationId = props.conversation.id;
  const { id, name } = ia.value;
  try {
    const { data } = await ConversationApi.assignAgent({
      conversationId,
      agentId: id,
      assigneeType: 'AgentBot',
    });
    store.dispatch('setCurrentChatAssignee', {
      conversationId,
      assignee: data,
      assigneeType: 'AgentBot',
    });
    useAlert(t('CONVERSA_CANAL.DEVOLVER.DEVOLVIDA', { nome: name }));
  } catch {
    useAlert(t('CONVERSA_CANAL.DEVOLVER.FALHOU'));
  } finally {
    devolvendo.value = false;
  }
};
</script>

<template>
  <p
    v-show="visivel"
    class="flex flex-wrap items-center gap-x-2 gap-y-0.5 mx-2 mb-2 text-xs text-n-slate-11"
    data-devolver-para-ia
  >
    <span
      class="i-lucide-sparkles size-3.5 flex-shrink-0 text-n-iris-11"
      aria-hidden="true"
    />
    <span>{{ t('CONVERSA_CANAL.DEVOLVER.VEIO_DE', { nome: ia?.name }) }}</span>
    <button
      v-tooltip.top="t('CONVERSA_CANAL.DEVOLVER.DICA', { nome: ia?.name })"
      type="button"
      :disabled="devolvendo"
      class="inline-flex items-center px-2 -mx-2 text-xs font-medium rounded outline-none min-h-11 text-n-iris-11 hover:underline disabled:opacity-60 focus-visible:ring-2 focus-visible:ring-n-iris-8"
      @click="devolver"
    >
      {{ t('CONVERSA_CANAL.DEVOLVER.PARA', { nome: ia?.name }) }}
    </button>
  </p>
</template>
