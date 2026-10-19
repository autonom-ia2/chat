<script setup>
// #1872 — aviso embaixo da sugestão da IA (as {{variáveis}} mudaram). Avisa; não bloqueia.
defineProps({
  texto: { type: String, required: true },
});
</script>

<template>
  <p
    role="status"
    class="mb-2 flex items-start gap-2 rounded-lg bg-n-amber-3 px-3 py-2 text-sm text-n-amber-11"
    data-aviso-da-sugestao
  >
    <span class="i-lucide-triangle-alert mt-0.5 size-4 flex-shrink-0" />
    {{ texto }}
  </p>
</template>
