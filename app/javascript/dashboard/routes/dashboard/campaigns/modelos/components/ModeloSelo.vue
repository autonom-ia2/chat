<script setup>
import { computed } from 'vue';
import { SITUACOES } from '../constants';

// A situação do modelo em palavras simples, com cor e ícone.
const props = defineProps({
  situacao: { type: String, required: true },
});

const visual = computed(() => SITUACOES[props.situacao] || SITUACOES.pausado);
</script>

<template>
  <span
    :data-selo="situacao"
    class="inline-flex items-center gap-1.5 px-2.5 py-1 text-sm font-medium rounded-full whitespace-nowrap"
    :class="visual.selo"
  >
    <span class="size-4" :class="visual.icone" aria-hidden="true" />
    {{ $t(`MODELOS_WHATSAPP.SITUACOES.${situacao}.ROTULO`) }}
  </span>
</template>
