<script setup>
// #2894 — o link discreto de volta ao topo da ficha ("‹ Pessoas"). O texto visível
// é curto; `rotulo` diz o destino inteiro para o leitor de tela.
defineProps({
  texto: { type: String, required: true },
  rotulo: { type: String, required: true },
});
const emit = defineEmits(['voltar']);
</script>

<template>
  <button
    type="button"
    data-relacionamentos="voltar"
    :aria-label="rotulo"
    class="inline-flex items-center self-start gap-1 text-sm font-medium rounded-lg min-h-11 text-n-slate-11 hover:text-n-slate-12 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
    @click="emit('voltar')"
  >
    <span
      class="size-4 i-lucide-chevron-left rtl:rotate-180"
      aria-hidden="true"
    />
    {{ texto }}
  </button>
</template>
