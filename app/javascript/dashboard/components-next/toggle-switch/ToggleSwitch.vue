<script setup>
// #1487 — liga/desliga com área de toque de 44 px (o Switch do components-next tem 16 px de altura), com
// <input type="checkbox" role="switch"> de verdade. Mesma anatomia do FunilInterruptor (#1384), sem o CRM.
// Fica dentro de um <label> com o texto; `label` dá o nome quando o texto ao lado não diz o que liga.
defineProps({
  label: { type: String, default: undefined },
  disabled: { type: Boolean, default: false },
});
const on = defineModel({ type: Boolean, default: false });
</script>

<template>
  <span class="relative inline-flex items-center min-h-11 min-w-11 shrink-0">
    <input
      v-model="on"
      type="checkbox"
      role="switch"
      :aria-label="label"
      :disabled="disabled"
      class="sr-only peer"
    />
    <span
      aria-hidden="true"
      class="h-7 w-12 rounded-full bg-n-slate-6 transition-colors after:absolute after:start-1 after:top-1/2 after:size-5 after:-translate-y-1/2 after:rounded-full after:bg-white after:shadow after:transition-transform peer-checked:bg-n-brand peer-checked:after:translate-x-5 rtl:peer-checked:after:-translate-x-5 peer-focus-visible:outline peer-focus-visible:outline-2 peer-focus-visible:outline-offset-2 peer-focus-visible:outline-n-brand peer-disabled:opacity-50"
    />
  </span>
</template>
