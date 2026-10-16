<script setup>
import { computed, ref } from 'vue';

// #1487 — escolha de um entre poucos valores dentro da própria frase: botões, um marcado. Grupo de rádio do
// WAI-ARIA (setas trocam e marcam; Tab entra só no marcado), alvo de toque de 44 px. Mesma anatomia do
// FunilTempoNaFrase (#1589), genérico: as opções chegam prontas, { value, label }.
const props = defineProps({
  options: { type: Array, required: true },
  label: { type: String, required: true },
});
const model = defineModel({ type: [String, Number], default: null });

const buttons = ref([]);
// Nenhum marcado (valor fora das opções): o primeiro recebe o Tab.
const hasChecked = computed(() =>
  props.options.some(option => option.value === model.value)
);

const check = index => {
  const total = props.options.length;
  const next = (index + total) % total;
  model.value = props.options[next].value;
  buttons.value[next]?.focus();
};
const ARROWS = { ArrowRight: 1, ArrowDown: 1, ArrowLeft: -1, ArrowUp: -1 };
const onKeydown = (event, index) => {
  const step = ARROWS[event.key];
  if (!step) return;
  event.preventDefault();
  check(index + step);
};
</script>

<template>
  <span
    role="radiogroup"
    :aria-label="label"
    class="grid w-full grid-flow-col gap-1 p-1 my-2 border auto-cols-fr rounded-2xl sm:inline-flex sm:w-fit border-n-strong bg-n-alpha-1"
    data-sentence-choice
  >
    <button
      v-for="(option, index) in options"
      :key="option.value"
      ref="buttons"
      type="button"
      role="radio"
      :aria-checked="model === option.value"
      :tabindex="
        model === option.value || (!hasChecked && index === 0) ? 0 : -1
      "
      :data-choice="option.value"
      class="min-h-11 whitespace-nowrap rounded-xl px-0.5 text-sm font-semibold outline-none transition-colors focus-visible:ring-2 focus-visible:ring-n-blue-8 sm:px-4 sm:text-base"
      :class="
        model === option.value
          ? 'bg-n-blue-9 text-white shadow-sm'
          : 'text-n-slate-12 hover:bg-n-alpha-3'
      "
      @click="model = option.value"
      @keydown="onKeydown($event, index)"
    >
      {{ option.label }}
    </button>
  </span>
</template>
