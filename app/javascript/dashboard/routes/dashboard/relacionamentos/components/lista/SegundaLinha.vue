<script setup>
// #2894 — a segunda linha de uma pessoa ou empresa. Cada informação é um bloco:
// no celular uma por linha, sem "·" (que ficaria pendurado no fim da linha);
// de `sm` para cima ficam todas na mesma linha, separadas por "·".
defineProps({
  partes: { type: Array, required: true },
});
</script>

<template>
  <p data-segunda-linha class="min-w-0 m-0 text-sm break-words text-n-slate-11">
    <template v-for="(parte, indice) in partes" :key="indice">
      <span v-if="indice > 0" class="hidden sm:inline"> · </span>
      <span class="block sm:inline">{{ parte }}</span>
    </template>
  </p>
</template>
