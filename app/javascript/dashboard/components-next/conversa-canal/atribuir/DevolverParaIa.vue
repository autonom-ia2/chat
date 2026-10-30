<script setup>
// #2067: "Devolver para <agente>", numa linha calma acima da barra de escrever (como o aviso
// do WhatsApp API: no fluxo da caixa de resposta, sem fundo próprio, nunca por cima da
// conversa). Só com a flag da conta, só na conversa que é MINHA (decisão do Rodrigo, 22/10:
// não aparece na conversa de colega) e só quando ela veio de um agente de IA; quem diz de
// qual, e por onde ela volta, é o servidor (meta.veio_da_ia, Crm::Passagens::VeioDaIa):
// - `ia` (agente nosso, com a Fase 2): pelo "Passar para" (POST passar_para), que dispara a
//   passagem completa (evento, turno refeito, recusas com motivo);
// - `robo` (robô de outro sistema, ou conta sem a Fase 2): pela atribuição de robô.
// A linha é baixa; o botão mantém o alvo de toque de 44 px por margem negativa.
import { computed, ref } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import ConversationApi from 'dashboard/api/inbox/conversation';
import PassarParaAPI from 'dashboard/api/passarPara';
import { useAlert } from 'dashboard/composables';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import { isAssignedToUser } from 'dashboard/helper/assigneeHelper';

const props = defineProps({
  conversation: { type: Object, required: true },
});

const store = useStore();
const { t } = useI18n();
const devolvendo = ref(false);
// Recusas do "Passar para" que a linha explica; as outras viram "não deu, tente de novo".
const RECUSAS = [
  'nao_atende_cliente',
  'sem_vinculo_na_caixa',
  'conversa_resolvida',
  'fase2_desligada',
];

const ligado = computed(() =>
  Boolean(
    store.getters['accounts/isFeatureEnabledonAccount']?.(
      store.getters.getCurrentAccountId,
      FEATURE_FLAGS.FICAR_COM_A_CONVERSA_AO_ENVIAR
    )
  )
);
const eu = computed(() => store.getters.getCurrentUser);
const ia = computed(() => props.conversation?.meta?.veio_da_ia || null);
const nome = computed(
  () => ia.value?.name || t('CONVERSA_CANAL.DEVOLVER.A_IA')
);
// Sem nome: "Esta conversa veio da IA" (e não "veio de a IA").
const veioDe = computed(() =>
  ia.value?.name
    ? t('CONVERSA_CANAL.DEVOLVER.VEIO_DE', { nome: ia.value.name })
    : t('CONVERSA_CANAL.DEVOLVER.VEIO_DA_IA')
);
const visivel = computed(
  () =>
    ligado.value &&
    isAssignedToUser(props.conversation, eu.value?.id) &&
    Boolean(ia.value?.id)
);

const devolverPeloPassarPara = async conversationId => {
  const { data } = await PassarParaAPI.passar(conversationId, {
    tipo: 'ia',
    id: ia.value.id,
  });
  return data?.com_ia
    ? { id: data.com_ia.bot_id, name: data.com_ia.name }
    : null;
};

const devolverPelaAtribuicao = async conversationId => {
  const { data } = await ConversationApi.assignAgent({
    conversationId,
    agentId: ia.value.id,
    assigneeType: 'AgentBot',
  });
  return data;
};

const textoDaRecusa = erro => {
  const codigo = erro?.response?.data?.codigo;
  return RECUSAS.includes(codigo)
    ? t(`CONVERSA_CANAL.DEVOLVER.RECUSA.${codigo.toUpperCase()}`, {
        nome: nome.value,
      })
    : t('CONVERSA_CANAL.DEVOLVER.FALHOU');
};

const devolver = async () => {
  if (devolvendo.value || !visivel.value) return;
  devolvendo.value = true;
  const conversationId = props.conversation.id;
  const quem = nome.value;
  try {
    const robo =
      ia.value.tipo === 'ia'
        ? await devolverPeloPassarPara(conversationId)
        : await devolverPelaAtribuicao(conversationId);
    if (robo) {
      store.dispatch('setCurrentChatAssignee', {
        conversationId,
        assignee: robo,
        assigneeType: 'AgentBot',
      });
    }
    useAlert(t('CONVERSA_CANAL.DEVOLVER.DEVOLVIDA', { nome: quem }));
  } catch (erro) {
    useAlert(textoDaRecusa(erro));
  } finally {
    devolvendo.value = false;
  }
};
</script>

<template>
  <!-- Raiz fixa (contents: sem caixa no layout) para o v-if não ficar na raiz (vue/no-root-v-if). -->
  <div class="contents">
    <p
      v-if="visivel"
      class="flex flex-wrap items-center gap-x-2 mx-2 mb-1 text-xs leading-5 text-n-slate-11"
      data-devolver-para-ia
    >
      <span
        class="i-lucide-sparkles size-3.5 flex-shrink-0 text-n-iris-11"
        aria-hidden="true"
      />
      <span>{{ veioDe }}</span>
      <button
        v-tooltip.top="t('CONVERSA_CANAL.DEVOLVER.DICA', { nome })"
        type="button"
        :disabled="devolvendo"
        class="inline-flex items-center px-2 -mx-2 -my-3 text-xs font-medium rounded outline-none min-h-11 text-n-iris-11 hover:underline disabled:opacity-60 focus-visible:ring-2 focus-visible:ring-n-iris-8"
        @click="devolver"
      >
        {{ t('CONVERSA_CANAL.DEVOLVER.PARA', { nome }) }}
      </button>
    </p>
  </div>
</template>
