<script setup>
// #2202 — o chip do status ("Resolvidas ✕", "Adiadas ✕", "Pendentes ✕", "Todos os status ✕") no
// começo da linha das pílulas, sempre que a lista não está nas abertas. O ✕ volta para as abertas.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

const props = defineProps({
  status: { type: String, required: true },
});
const emit = defineEmits(['limpar']);
const { t } = useI18n();

const NOMES = {
  resolved: 'RESOLVIDAS',
  snoozed: 'ADIADAS',
  pending: 'PENDENTES',
  all: 'TODOS_OS_STATUS',
};
// Status que a lista nova não nomeia: o nome que o filtro de sempre dá a ele.
const nome = computed(() =>
  NOMES[props.status]
    ? t(`LISTA_DE_CONVERSAS.CABECALHO.${NOMES[props.status]}`)
    : t(`CHAT_LIST.CHAT_STATUS_FILTER_ITEMS.${props.status}.TEXT`)
);
</script>

<template>
  <button
    type="button"
    data-chip-do-status
    :aria-label="`${nome}. ${t('LISTA_DE_CONVERSAS.CABECALHO.VOLTAR_ABERTAS')}`"
    class="relative inline-flex items-center flex-shrink-0 h-8 gap-1 px-3 text-sm font-medium border rounded-full border-n-brand bg-n-brand text-white after:absolute after:-inset-y-1.5 after:inset-x-0 after:content-['']"
    @click="emit('limpar')"
  >
    {{ nome }}
    <span class="i-lucide-x size-4" aria-hidden="true" />
  </button>
</template>
