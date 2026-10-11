<script setup>
import { computed } from 'vue';

// #1301 — faixa de aviso das Ferramentas (protótipo .band): azul informa, âmbar alerta, teal
// confirma. "solta" é o aviso de linha, sem caixa, logo abaixo de um campo. O texto fica sempre
// slate 12 (o âmbar 11 sobre âmbar 2 não chega ao AA); a cor vai no ícone e na caixa.
const props = defineProps({
  tom: {
    type: String,
    default: 'azul',
    validator: v => ['azul', 'ambar', 'teal'].includes(v),
  },
  icone: { type: String, default: '' },
  solta: { type: Boolean, default: false },
});

const ICONES = {
  azul: 'i-lucide-info',
  ambar: 'i-lucide-triangle-alert',
  teal: 'i-lucide-circle-check',
};

const CORES = {
  azul: 'text-n-blue-11',
  ambar: 'text-n-amber-11',
  teal: 'text-n-teal-11',
};

const CAIXAS = {
  azul: 'bg-n-blue-2 ring-n-blue-6',
  ambar: 'bg-n-amber-2 ring-n-amber-6',
  teal: 'bg-n-teal-2 ring-n-teal-6',
};

const classeDoIcone = computed(() => [
  props.icone || ICONES[props.tom],
  CORES[props.tom],
]);
</script>

<template>
  <div
    class="flex items-start text-sm text-n-slate-12"
    :class="
      solta
        ? 'gap-2'
        : ['gap-3 p-3 rounded-xl ring-1 ring-inset', CAIXAS[props.tom]]
    "
  >
    <span
      aria-hidden="true"
      class="mt-0.5 shrink-0"
      :class="[classeDoIcone, solta ? 'size-4' : 'size-5']"
    />
    <div class="flex flex-col min-w-0 gap-1 grow">
      <slot />
    </div>
  </div>
</template>
