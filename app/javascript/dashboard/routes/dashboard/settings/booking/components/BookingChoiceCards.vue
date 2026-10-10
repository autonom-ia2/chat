<script setup>
import { useId } from 'vue';

// Escolha única em cartões (jogo de avisos, prazo para mudar). Por baixo é um
// grupo de rádios de verdade: setas do teclado trocam a escolha e o leitor de
// tela ouve "1 de 3, selecionado". O cartão inteiro é o alvo (44 px ou mais).
defineProps({
  legend: { type: String, required: true },
  hint: { type: String, default: '' },
  // [{ value, label, hint?, badge? }]
  options: { type: Array, required: true },
  modelValue: { type: [String, Number], required: true },
});

const emit = defineEmits(['update:modelValue']);
const name = useId();
</script>

<template>
  <fieldset class="flex flex-col gap-3 p-0 m-0 border-0">
    <legend class="p-0 mb-1 text-base font-semibold text-n-slate-12">
      {{ legend }}
    </legend>
    <p v-if="hint" class="m-0 text-base text-n-slate-11">{{ hint }}</p>
    <div
      class="grid gap-3 grid-cols-[repeat(auto-fit,minmax(min(100%,13rem),1fr))]"
    >
      <label
        v-for="option in options"
        :key="option.value"
        :data-choice="option.value"
        class="relative flex flex-col gap-1 min-h-11 p-4 rounded-2xl cursor-pointer ring-inset bg-n-solid-1 transition has-[:checked]:ring-2 has-[:checked]:ring-n-blue-9 has-[:checked]:bg-n-blue-2 ring-1 ring-n-weak hover:ring-n-blue-7 has-[:focus-visible]:outline has-[:focus-visible]:outline-2 has-[:focus-visible]:outline-n-brand"
      >
        <input
          type="radio"
          class="sr-only"
          :name="name"
          :value="option.value"
          :checked="modelValue === option.value"
          @change="emit('update:modelValue', option.value)"
        />
        <span class="flex items-start justify-between gap-2">
          <span class="text-base font-semibold text-n-slate-12">
            {{ option.label }}
          </span>
          <span
            v-if="option.badge"
            class="px-2 py-0.5 text-sm font-semibold rounded-full shrink-0 bg-n-blue-3 text-n-blue-11"
          >
            {{ option.badge }}
          </span>
        </span>
        <span v-if="option.hint" class="text-base text-n-slate-11">
          {{ option.hint }}
        </span>
      </label>
    </div>
  </fieldset>
</template>
