<script setup>
import { useI18n } from 'vue-i18n';

// #2776 — "mostrar antes de fazer": uma conversa curta de exemplo com o que o agente passa a conseguir.
defineProps({
  cliente: { type: String, required: true },
  resposta: { type: String, required: true },
  agente: { type: String, default: '' },
});

const { t } = useI18n();
</script>

<template>
  <div
    data-vitrine-conversa
    class="flex flex-col gap-3 p-4 rounded-2xl bg-n-alpha-1 ring-1 ring-inset ring-n-weak"
  >
    <div class="flex flex-col items-start gap-1">
      <span class="text-xs font-medium text-n-slate-11">
        {{ t('AGENTS.VITRINE.DETALHE.CLIENTE') }}
      </span>
      <p
        class="m-0 max-w-[85%] px-3.5 py-2.5 text-sm rounded-2xl rounded-tl-md bg-n-solid-1 text-n-slate-12 ring-1 ring-inset ring-n-weak"
      >
        {{ cliente }}
      </p>
    </div>
    <div class="flex flex-col items-end gap-1">
      <span class="text-xs font-medium text-n-slate-11">
        {{ agente || t('AGENTS.VITRINE.DETALHE.AGENTE') }}
      </span>
      <p
        class="m-0 max-w-[85%] px-3.5 py-2.5 text-sm rounded-2xl rounded-tr-md bg-n-blue-9 text-white"
      >
        {{ resposta }}
      </p>
    </div>
  </div>
</template>
