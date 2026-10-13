<script setup>
// #1384 — liga/desliga com área de toque de 44 px (o Switch do
// components-next tem 16 px de altura). Fica dentro de um <label> com o texto.
defineProps({
  // Nome para o leitor de tela quando o texto ao lado não diz o que liga.
  rotulo: { type: String, default: undefined },
});
const ligado = defineModel({ type: Boolean, default: false });
</script>

<template>
  <span class="relative inline-flex min-h-11 min-w-11 shrink-0 items-center">
    <input
      v-model="ligado"
      type="checkbox"
      role="switch"
      :aria-label="rotulo"
      class="peer sr-only"
    />
    <span
      aria-hidden="true"
      class="h-7 w-12 rounded-full bg-n-slate-6 transition-colors after:absolute after:start-1 after:top-1/2 after:size-5 after:-translate-y-1/2 after:rounded-full after:bg-white after:shadow after:transition-transform peer-checked:bg-n-brand peer-checked:after:translate-x-5 rtl:peer-checked:after:-translate-x-5 peer-focus-visible:outline peer-focus-visible:outline-2 peer-focus-visible:outline-offset-2 peer-focus-visible:outline-n-brand"
    />
  </span>
</template>
