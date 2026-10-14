<script setup>
// #1181 (DECISOES.md item 3) — "ideias para começar": só no primeiro turno, preenchem o campo e a
// pessoa pode editar antes de mandar. Não fingem responder pergunta da IA.
const props = defineProps({
  opcoes: { type: Array, required: true },
  rotulo: { type: String, default: '' },
  desabilitado: { type: Boolean, default: false },
});

const emit = defineEmits(['escolher']);

const escolher = opcao => {
  if (props.desabilitado) return;
  emit('escolher', opcao);
};
</script>

<template>
  <div
    role="group"
    :aria-label="rotulo || undefined"
    class="flex flex-wrap gap-2"
  >
    <button
      v-for="opcao in opcoes"
      :key="opcao"
      type="button"
      :aria-disabled="desabilitado ? 'true' : undefined"
      class="px-4 text-sm transition rounded-full min-h-11 bg-n-solid-1 text-n-slate-12 ring-1 ring-inset ring-n-slate-7 hover:bg-n-slate-2 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-11 aria-disabled:cursor-not-allowed aria-disabled:opacity-60"
      @click="escolher(opcao)"
    >
      {{ opcao }}
    </button>
  </div>
</template>
