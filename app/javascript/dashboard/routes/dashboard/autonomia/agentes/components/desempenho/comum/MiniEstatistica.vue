<script setup>
// #2226 v2 — um número pequeno com a legenda embaixo (total, pico, média…). A cor é opcional e
// segue a série (desempenhoCores).
import { computed } from 'vue';
import { corDe } from '../../../utils/desempenhoCores';

const props = defineProps({
  valor: { type: [String, Number], required: true },
  legenda: { type: String, required: true },
  cor: { type: String, default: '' },
});

const classeDoValor = computed(() =>
  props.cor ? corDe(props.cor).texto : 'text-n-slate-12'
);
</script>

<template>
  <div data-mini class="flex flex-col px-3 py-2 rounded-xl bg-n-alpha-1">
    <span
      class="text-lg font-semibold leading-tight tabular-nums"
      :class="classeDoValor"
    >
      {{ valor }}
    </span>
    <span class="text-xs text-n-slate-11">{{ legenda }}</span>
  </div>
</template>
