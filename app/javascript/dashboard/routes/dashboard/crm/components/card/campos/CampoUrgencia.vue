<script setup>
import { useI18n } from 'vue-i18n';
import { URGENCIAS } from '../useCardNegocio';

// #1423 — a urgência em quatro botões (baixa, média, alta, urgente), na
// criação e no Negócio.
defineProps({
  somenteLeitura: { type: Boolean, default: false },
});
const urgencia = defineModel({ type: String, default: 'medium' });
const { t } = useI18n();
</script>

<template>
  <fieldset class="m-0 flex flex-col gap-2 border-0 p-0" data-campo-urgencia>
    <legend class="mb-1 p-0 text-sm font-medium text-n-slate-12">
      {{ t('CRM_CARD.NEGOCIO.URGENCIA') }}
    </legend>
    <div class="grid grid-cols-2 gap-2 sm:grid-cols-4">
      <button
        v-for="opcao in URGENCIAS"
        :key="opcao"
        type="button"
        :data-urgencia="opcao"
        :aria-pressed="urgencia === opcao"
        :disabled="somenteLeitura"
        class="min-h-11 rounded-xl px-3 ring-1 ring-inset text-sm font-medium transition focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-9 disabled:cursor-not-allowed"
        :class="
          urgencia === opcao
            ? 'ring-n-blue-8 bg-n-blue-2 text-n-blue-11'
            : 'ring-n-weak bg-n-solid-1 text-n-slate-12 hover:ring-n-slate-7 disabled:opacity-60'
        "
        @click="urgencia = opcao"
      >
        {{ t(`CRM_KANBAN.PRIORITY.${opcao.toUpperCase()}`) }}
      </button>
    </div>
  </fieldset>
</template>
