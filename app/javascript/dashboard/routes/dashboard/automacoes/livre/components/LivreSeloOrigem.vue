<script setup>
import { computed } from 'vue';

// #2414 F0 — de onde a automação vem: "da conversa", "do funil" ou "do jeito
// antigo" (ainda num motor antigo). Receita de pacote ganha o selo do pacote.
const props = defineProps({
  automacao: { type: Object, required: true },
});

const selo = computed(() => {
  if (props.automacao.jeitoAntigo)
    return {
      chave: 'ANTIGO',
      icone: 'i-lucide-history',
      tom: 'bg-n-amber-3 text-n-amber-11',
    };
  if (props.automacao.origem === 'funil')
    return {
      chave: 'FUNIL',
      icone: 'i-lucide-square-kanban',
      tom: 'bg-n-violet-3 text-n-violet-11',
    };
  return {
    chave: 'CONVERSA',
    icone: 'i-lucide-message-circle',
    tom: 'bg-n-blue-3 text-n-blue-11',
  };
});
</script>

<template>
  <span class="inline-flex flex-wrap items-center gap-1.5">
    <span
      data-origem
      class="inline-flex items-center gap-1 px-2.5 py-0.5 text-xs font-medium rounded-full"
      :class="selo.tom"
    >
      <span class="size-3" :class="selo.icone" aria-hidden="true" />
      {{ $t(`AUTOMACAO_LIVRE.ORIGEM.${selo.chave}`) }}
    </span>
    <span
      v-if="automacao.pacote"
      data-pacote
      class="inline-flex items-center gap-1 px-2.5 py-0.5 text-xs font-medium rounded-full bg-n-teal-3 text-n-teal-11"
    >
      <span class="i-lucide-package size-3" aria-hidden="true" />
      {{ $t('AUTOMACAO_LIVRE.ORIGEM.PACOTE', { pacote: automacao.pacote }) }}
    </span>
  </span>
</template>
