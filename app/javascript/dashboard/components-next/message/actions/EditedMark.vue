<script setup>
// O selo "editada" (chat#1709, fase 3), com os textos anteriores na dica: a mensagem foi editada pelo cliente no
// WhatsApp ou pelo atendente no painel. O histórico fica em `content_attributes.edit_history`.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

const props = defineProps({
  history: { type: Array, default: () => [] },
});

const { t } = useI18n();
const previous = computed(() =>
  (Array.isArray(props.history) ? props.history : [])
    .map(entry => (typeof entry?.content === 'string' ? entry.content : ''))
    .filter(Boolean)
);
const tooltip = computed(() =>
  previous.value.length
    ? `${t('MESSAGE_ACTIONS.EDIT_HISTORY')}\n${previous.value.join('\n—\n')}`
    : ''
);
</script>

<template>
  <span
    v-tooltip="tooltip"
    data-edited-mark
    class="text-xs text-n-slate-11 inline-flex items-center gap-1"
  >
    <span class="i-lucide-pencil size-3" aria-hidden="true" />
    {{ t('MESSAGE_ACTIONS.EDITED') }}
  </span>
</template>
