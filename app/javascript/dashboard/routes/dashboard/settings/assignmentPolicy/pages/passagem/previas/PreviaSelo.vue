<script setup>
// #1385 — o selo da coluna da direita, no estilo do funil (#1384): verde, com ponto. "Agora" para o que já vale e
// "Prévia" para o exemplo.
const props = defineProps({
  tipo: { type: String, default: 'previa' },
});

const CHAVES = { agora: 'SELO_AGORA', previa: 'SELO' };
const chave = () => `CRM_KANBAN.PASSAGEM.PREVIA.${CHAVES[props.tipo]}`;
</script>

<template>
  <span
    data-selo
    :data-selo-tipo="tipo"
    class="inline-flex shrink-0 items-center gap-1.5 rounded-lg bg-n-teal-3 px-2 py-0.5 text-xs font-semibold text-n-teal-11"
  >
    <span class="size-1.5 rounded-full bg-n-teal-9" aria-hidden="true" />
    {{ $t(chave()) }}
  </span>
</template>
