<script setup>
// #1149 — nome do funil com a bolinha da cor dele.
defineProps({
  nome: { type: String, required: true },
  cor: { type: String, required: true },
});
</script>

<template>
  <span
    class="inline-flex items-center gap-2 rounded-lg bg-n-alpha-2 px-2.5 py-1 text-sm font-medium text-n-slate-12"
  >
    <span class="size-2.5 rounded-full" :class="cor" aria-hidden="true" />
    {{ nome }}
  </span>
</template>
