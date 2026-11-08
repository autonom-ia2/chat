<script setup>
// #2138 — os itens novos do ⋯ do topo da conversa, só com o painel novo:
// "Mudar time ou prioridade" (ou "Mudar prioridade", quando a conta não tem time)
// e "Acompanhar esta conversa" / "Deixar de acompanhar". Fica ao lado do
// MoreActions.vue (do Chatwoot), que só soma `itens` à lista dele e passa a ação
// para `agir`. O diálogo de time e prioridade é desenhado aqui.
// #2202 (PR 3): "Etiquetas desta conversa", para todas as contas (sem a chave do
// painel novo), só para quem opera a conversa — a mesma regra do painel antigo.
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { useCanOperateConversation } from 'dashboard/composables/useCanOperateConversation';
import CrmMeuAcessoAPI from 'dashboard/api/crmMeuAcesso';
import { usePainelNovo } from '../usePainelNovo';
import { mudarAcompanhar } from './acompanhar';
import TimeEPrioridadeDialog from './TimeEPrioridadeDialog.vue';
import EtiquetasDaConversaDialog from '../etiquetas/EtiquetasDaConversaDialog.vue';

const props = defineProps({
  conversa: { type: Object, required: true },
  // Devolve o foco ao ⋯ quando a escolha de etiquetas fecha.
  voltarFoco: { type: Function, default: null },
});

const ACAO_TIME = 'painel_novo_time_e_prioridade';
const ACAO_ACOMPANHAR = 'painel_novo_acompanhar';
const ACAO_ETIQUETAS = 'etiquetas_da_conversa';

const { t } = useI18n();
const store = useStore();
const ligado = usePainelNovo();
const eu = useMapGetter('getCurrentUser');
const times = useMapGetter('teams/getTeams');
const acompanhantesDe = useMapGetter(
  'conversationWatchers/getByConversationId'
);
const dialogo = ref(null);
const etiquetas = ref(null);
const podeOperar = useCanOperateConversation(computed(() => props.conversa));
const caixasRestritas = ref([]);

const temTime = computed(() => (times.value || []).length > 0);
const acompanho = computed(() =>
  (acompanhantesDe.value(props.conversa?.id) || []).some(
    pessoa => pessoa.id === eu.value?.id
  )
);
// #1148/#1149: quem tem acesso restrito por funil nesta caixa não se inclui
// (o servidor recusa do mesmo jeito). Sair continua livre.
const naoPodeSeIncluir = computed(() =>
  caixasRestritas.value.includes(Number(props.conversa?.inbox_id))
);

const itemDeEtiquetas = computed(() =>
  podeOperar.value
    ? [
        {
          icon: 'i-lucide-tags',
          label: t('PAINEL_DO_CONTATO.MENU_DO_TOPO.ETIQUETAS'),
          action: ACAO_ETIQUETAS,
          value: ACAO_ETIQUETAS,
        },
      ]
    : []
);

const itensDoPainelNovo = computed(() => {
  if (!ligado.value) return [];
  const lista = [
    {
      icon: 'i-lucide-flag',
      label: temTime.value
        ? t('PAINEL_DO_CONTATO.MENU_DO_TOPO.TIME_E_PRIORIDADE')
        : t('PAINEL_DO_CONTATO.MENU_DO_TOPO.SO_PRIORIDADE'),
      action: ACAO_TIME,
      value: ACAO_TIME,
    },
  ];
  if (acompanho.value || !naoPodeSeIncluir.value) {
    lista.push({
      icon: acompanho.value ? 'i-lucide-bell-off' : 'i-lucide-bell',
      label: acompanho.value
        ? t('PAINEL_DO_CONTATO.MENU_DO_TOPO.DEIXAR')
        : t('PAINEL_DO_CONTATO.MENU_DO_TOPO.ACOMPANHAR'),
      action: ACAO_ACOMPANHAR,
      value: ACAO_ACOMPANHAR,
    });
  }
  return lista;
});

const itens = computed(() => [
  ...itensDoPainelNovo.value,
  ...itemDeEtiquetas.value,
]);

const MENSAGENS_DE_ERRO = {
  'participants.self_add_restricted': () =>
    t('CONVERSATION_PARTICIPANTS.API.SELF_ADD_RESTRICTED'),
};

const alternarAcompanhar = async () => {
  const acompanhar = !acompanho.value;
  const conversationId = props.conversa.id;
  try {
    const ficou = await mudarAcompanhar({
      conversationId,
      euId: eu.value.id,
      acompanhar,
    });
    if (!ficou) throw new Error('não ficou como pedido');
    useAlert(
      acompanhar
        ? t('PAINEL_DO_CONTATO.MENU_DO_TOPO.ACOMPANHANDO')
        : t('PAINEL_DO_CONTATO.MENU_DO_TOPO.DEIXOU')
    );
  } catch (erro) {
    const codigo = erro?.response?.data?.code;
    useAlert(
      MENSAGENS_DE_ERRO[codigo]?.() || t('PAINEL_DO_CONTATO.MENU_DO_TOPO.ERRO')
    );
  }
  store
    .dispatch('conversationWatchers/show', { conversationId })
    .catch(() => {});
};

// true quando a ação é daqui (quem chama não faz mais nada).
const agir = action => {
  if (action === ACAO_ETIQUETAS && podeOperar.value) {
    etiquetas.value?.abrir(props.voltarFoco);
    return true;
  }
  if (!ligado.value) return false;
  if (action === ACAO_TIME) {
    dialogo.value?.abrir();
    return true;
  }
  if (action === ACAO_ACOMPANHAR) {
    alternarAcompanhar();
    return true;
  }
  return false;
};

const carregarCaixasRestritas = async () => {
  if (window.globalConfig?.CRM_KANBAN_ENABLED !== 'true') return;
  try {
    const { data } = await CrmMeuAcessoAPI.get();
    caixasRestritas.value = data.payload?.restricted_inbox_ids || [];
  } catch {
    // Sem a resposta, o item aparece como hoje no painel antigo; o servidor
    // continua recusando a autoinclusão de quem é restrito.
  }
};

// Os times já vêm com o menu lateral (Sidebar.vue). Quem acompanha é lido por
// conversa, para o item dizer "Acompanhar" ou "Deixar de acompanhar".
watch(
  ligado,
  sim => {
    if (sim) carregarCaixasRestritas();
  },
  { immediate: true }
);
watch(
  () => [ligado.value, props.conversa?.id],
  ([sim, conversationId]) => {
    if (!sim || !conversationId) return;
    // Sem a leitura, o item diz "Acompanhar"; ao tocar, a lista é lida de novo.
    store
      .dispatch('conversationWatchers/show', { conversationId })
      .catch(() => {});
  },
  { immediate: true }
);

defineExpose({ itens, agir });
</script>

<template>
  <div class="contents">
    <TimeEPrioridadeDialog
      v-if="ligado"
      ref="dialogo"
      :conversa="conversa"
      :times="times || []"
    />
    <EtiquetasDaConversaDialog v-if="podeOperar" ref="etiquetas" />
  </div>
</template>
