<script setup>
// #2138 — "linha que abre": texto, contagem e seta, 44 px, fundo ao passar o mouse.
defineProps({
  texto: { type: String, required: true },
  icone: { type: String, default: 'i-lucide-chevron-right' },
});
defineEmits(['abrir']);
</script>

<template>
  <button
    type="button"
    class="flex items-center w-full gap-2 px-2 -mx-2 text-sm text-left rounded-lg min-h-11 text-n-slate-12 hover:bg-n-alpha-2 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
    @click="$emit('abrir')"
  >
    <span class="flex-1 min-w-0">{{ texto }}</span>
    <span :class="icone" class="flex-shrink-0 size-4 text-n-slate-11" />
  </button>
</template>
