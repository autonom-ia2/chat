<script setup>
// #2138 — "Quem cuida": uma frase de quem está com a conversa e, só com valor,
// a frase de time e prioridade. Nas contas sem a Fase 2 dos Agentes, uma ação
// só ("Trocar" ou "Escolher quem cuida"), com a escolha ali mesmo; com a Fase 2,
// quem passa é o "Passar para…" do topo, e o bloco não tem botão.
import { computed, nextTick, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { useAgentsList } from 'dashboard/composables/useAgentsList';
import {
  QUEM_ESTA,
  quemEstaComAConversa,
} from 'dashboard/components-next/conversa-canal/atribuir/quemEstaComAConversa';
import Button from 'dashboard/components-next/button/Button.vue';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import BlocoDoPainel from './BlocoDoPainel.vue';

const props = defineProps({
  conversation: { type: Object, required: true },
  podeOperar: { type: Boolean, default: false },
  fase2: { type: Boolean, default: false },
});

const { t } = useI18n();
const store = useStore();
const eu = useMapGetter('getCurrentUser');
const { agentsList } = useAgentsList(false, { includeAIAssignees: true });

const NINGUEM = 'ninguem';
const quem = computed(() =>
  quemEstaComAConversa(props.conversation, eu.value?.id)
);
const dono = computed(() => props.conversation?.meta?.assignee || {});

const fraseDeQuem = computed(() => {
  if (quem.value === QUEM_ESTA.MINHA)
    return t('PAINEL_DO_CONTATO.QUEM_CUIDA.VOCE');
  if (quem.value === QUEM_ESTA.COLEGA)
    return t('PAINEL_DO_CONTATO.QUEM_CUIDA.COLEGA', { nome: dono.value.name });
  if (quem.value === QUEM_ESTA.IA)
    return t('PAINEL_DO_CONTATO.QUEM_CUIDA.IA', { nome: dono.value.name });
  // Com a Fase 2 não há botão aqui: meia frase ensina o #2067 (assume ao enviar).
  return props.fase2 && props.podeOperar
    ? t('PAINEL_DO_CONTATO.QUEM_CUIDA.NINGUEM_AO_RESPONDER')
    : t('PAINEL_DO_CONTATO.QUEM_CUIDA.NINGUEM');
});

const NIVEIS = {
  low: () => t('CRM_CARD.URGENCIA.LOW'),
  medium: () => t('CRM_CARD.URGENCIA.MEDIUM'),
  high: () => t('CRM_CARD.URGENCIA.HIGH'),
  urgent: () => t('CRM_CARD.URGENCIA.URGENT'),
};
const fraseDeTime = computed(() => {
  const time = props.conversation?.meta?.team?.name;
  const nivel = NIVEIS[props.conversation?.priority]?.();
  if (time && nivel)
    return t('PAINEL_DO_CONTATO.QUEM_CUIDA.TIME_E_PRIORIDADE', { time, nivel });
  if (time) return t('PAINEL_DO_CONTATO.QUEM_CUIDA.SO_TIME', { time });
  if (nivel) return t('PAINEL_DO_CONTATO.QUEM_CUIDA.SO_PRIORIDADE', { nivel });
  return '';
});

const temAcao = computed(() => props.podeOperar && !props.fase2);
const rotuloDaAcao = computed(() =>
  quem.value === QUEM_ESTA.NINGUEM
    ? t('PAINEL_DO_CONTATO.QUEM_CUIDA.ESCOLHER')
    : t('PAINEL_DO_CONTATO.QUEM_CUIDA.TROCAR')
);

const chaveDe = (tipo, id) => `${tipo || 'User'}:${id}`;
const escolhaAtual = computed(() =>
  dono.value.id
    ? chaveDe(props.conversation.meta.assignee_type, dono.value.id)
    : NINGUEM
);
const escolha = ref(NINGUEM);
const escolhendo = ref(false);
const caixaDaEscolha = ref(null);
const escolhaRef = ref(null);

const grupos = computed(() => {
  const lista = agentsList.value || [];
  const pessoas = lista.filter(a => (a.assignee_type || 'User') === 'User');
  const ias = lista.filter(a => (a.assignee_type || 'User') !== 'User');
  const opcao = a => ({ value: chaveDe(a.assignee_type, a.id), label: a.name });
  return [
    {
      label: t('PAINEL_DO_CONTATO.QUEM_CUIDA.PESSOAS'),
      options: [
        {
          value: NINGUEM,
          label: t('PAINEL_DO_CONTATO.QUEM_CUIDA.NINGUEM_OPCAO'),
        },
        ...pessoas.map(opcao),
      ],
    },
    ...(ias.length
      ? [
          {
            label: t('PAINEL_DO_CONTATO.QUEM_CUIDA.GRUPO_IA'),
            options: ias.map(opcao),
          },
        ]
      : []),
  ];
});

const abrirEscolha = async () => {
  escolha.value = escolhaAtual.value;
  escolhendo.value = true;
  await nextTick();
  escolhaRef.value?.abrir();
};

// Fechou a lista sem escolher (clique fora ou foco saiu): volta o botão. O foco
// que sai do próprio botão ao abrir a lista (ele some da tela) não conta: o
// Chrome avisa essa saída, e sem a conferência a lista fechava na hora.
const saiuDaEscolha = evento => {
  if (!evento.target?.closest?.('[data-escolha-de-quem-cuida]')) return;
  if (!caixaDaEscolha.value?.contains(evento.relatedTarget)) {
    escolhendo.value = false;
  }
};

const trocar = async () => {
  escolhendo.value = false;
  if (escolha.value === escolhaAtual.value) return;
  const agente = (agentsList.value || []).find(
    a => chaveDe(a.assignee_type, a.id) === escolha.value
  );
  const pedido = escolha.value;
  await store.dispatch('assignAgent', {
    conversationId: props.conversation.id,
    agentId: agente ? agente.id : null,
    assigneeType: agente ? agente.assignee_type || 'User' : null,
  });
  // A action de hoje não devolve erro: o que não mudou na conversa não foi salvo.
  if (escolhaAtual.value !== pedido) {
    useAlert(t('PAINEL_DO_CONTATO.QUEM_CUIDA.ERRO'));
    return;
  }
  useAlert(
    agente
      ? t('PAINEL_DO_CONTATO.QUEM_CUIDA.AGORA_COM', { nome: agente.name })
      : t('PAINEL_DO_CONTATO.QUEM_CUIDA.AGORA_NINGUEM')
  );
};

// #2202 (PR 3): o título recebe o foco quando o bloco das etiquetas, logo
// abaixo, some com o foco dentro (tirou a última etiqueta).
const bloco = ref(null);
defineExpose({ focarTitulo: () => bloco.value?.focarTitulo() });
</script>

<template>
  <BlocoDoPainel
    ref="bloco"
    :titulo="t('PAINEL_DO_CONTATO.QUEM_CUIDA.TITULO')"
    focavel
  >
    <p class="m-0 text-sm text-n-slate-12" data-test-id="quem-cuida">
      {{ fraseDeQuem }}
    </p>
    <p v-if="fraseDeTime" class="m-0 text-sm text-n-slate-12">
      {{ fraseDeTime }}
    </p>
    <div v-if="temAcao" ref="caixaDaEscolha" @focusout="saiuDaEscolha">
      <ChoiceSelect
        v-if="escolhendo"
        ref="escolhaRef"
        v-model="escolha"
        data-escolha-de-quem-cuida
        :groups="grupos"
        :aria-label="t('PAINEL_DO_CONTATO.QUEM_CUIDA.ESCOLHA_TITULO')"
        class="w-full"
        @change="trocar"
      />
      <Button
        v-else
        :label="rotuloDaAcao"
        variant="link"
        color="blue"
        size="sm"
        class="min-h-11"
        @click="abrirEscolha"
      />
    </div>
  </BlocoDoPainel>
</template>
