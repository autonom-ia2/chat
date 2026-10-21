<script setup>
// #2067: "Devolver para <agente>". Só quando a conversa está com uma pessoa e veio de um
// agente de IA; conversa que nunca esteve com IA não mostra nada.
// - topo (a escolha): pílula no cabeçalho, junto das ações da conversa. Fica fora da
//   barra de escrever e aparece mesmo sem nada digitado.
// - barra (alternativa do protótipo, ?devolver=barra): linha calma acima da barra.
// Devolver usa a atribuição de hoje para robô (POST assignments, assignee_type AgentBot).
import { computed, ref } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import ConversationApi from 'dashboard/api/inbox/conversation';
import { useAlert } from 'dashboard/composables';
import { iaDeOrigem } from './prototipo2067';

const props = defineProps({
  conversation: { type: Object, required: true },
  forma: {
    type: String,
    default: 'topo',
    validator: valor => ['topo', 'barra'].includes(valor),
  },
});

const store = useStore();
const { t } = useI18n();
const devolvendo = ref(false);

const ia = computed(() => iaDeOrigem(props.conversation));
const comPessoa = computed(
  () =>
    props.conversation?.meta?.assignee_type === 'User' &&
    Boolean(props.conversation?.meta?.assignee)
);
const visivel = computed(() => comPessoa.value && Boolean(ia.value));
const rotulo = computed(() =>
  t('CONVERSA_CANAL.DEVOLVER.PARA', { nome: ia.value?.nome })
);

const devolver = async () => {
  if (devolvendo.value) return;
  devolvendo.value = true;
  const conversationId = props.conversation.id;
  try {
    const { data } = await ConversationApi.assignAgent({
      conversationId,
      agentId: ia.value.id,
      assigneeType: 'AgentBot',
    });
    store.dispatch('setCurrentChatAssignee', {
      conversationId,
      assignee: data,
      assigneeType: 'AgentBot',
    });
    useAlert(t('CONVERSA_CANAL.DEVOLVER.DEVOLVIDA', { nome: ia.value.nome }));
  } catch {
    useAlert(t('CONVERSA_CANAL.DEVOLVER.FALHOU'));
  } finally {
    devolvendo.value = false;
  }
};
</script>

<template>
  <template v-if="visivel">
    <button
      v-if="forma === 'topo'"
      v-tooltip.bottom="t('CONVERSA_CANAL.DEVOLVER.DICA', { nome: ia.nome })"
      type="button"
      :disabled="devolvendo"
      :aria-label="rotulo"
      data-devolver-para-ia
      class="group inline-flex items-center flex-shrink-0 h-8 gap-1.5 ps-1 pe-3 rounded-full text-sm font-medium transition-colors bg-n-iris-3 text-n-iris-11 hover:enabled:bg-n-iris-4 outline outline-1 outline-n-iris-6 disabled:opacity-60 focus-visible:ring-2 focus-visible:ring-n-iris-8"
      @click="devolver"
    >
      <span
        class="grid rounded-full size-6 place-content-center bg-n-iris-9 text-white"
        aria-hidden="true"
      >
        <span
          class="size-3.5"
          :class="devolvendo ? 'i-lucide-loader-circle animate-spin' : 'i-lucide-sparkles'"
        />
      </span>
      <span class="truncate max-w-[14rem]">{{ rotulo }}</span>
      <span
        class="i-lucide-undo-2 size-3.5 opacity-70 transition-transform group-hover:-translate-x-0.5"
        aria-hidden="true"
      />
    </button>
    <p
      v-else
      class="flex flex-wrap items-center gap-x-1.5 gap-y-0.5 mx-2 mb-2 text-xs text-n-slate-11"
      data-devolver-para-ia
    >
      <span
        class="i-lucide-sparkles size-3.5 flex-shrink-0 text-n-iris-11"
        aria-hidden="true"
      />
      <span>{{ t('CONVERSA_CANAL.DEVOLVER.VEIO_DE', { nome: ia.nome }) }}</span>
      <span class="text-n-slate-9" aria-hidden="true">·</span>
      <button
        type="button"
        :disabled="devolvendo"
        class="px-1 -mx-1 py-1 -my-1 text-xs font-medium rounded outline-none text-n-iris-11 hover:underline focus-visible:ring-2 focus-visible:ring-n-iris-8"
        @click="devolver"
      >
        {{ rotulo }}
      </button>
    </p>
  </template>
</template>
