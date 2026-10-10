<script setup>
// Escolha curta em botões lado a lado (7 ou 30 dias; só os meus ou equipe), sem lista nativa do navegador.
// Cada botão diz se está escolhido (aria-pressed) e tem 44 px de altura.
defineProps({
  modelValue: { type: [String, Number], required: true },
  options: { type: Array, required: true },
  label: { type: String, required: true },
  disabled: { type: Boolean, default: false },
});

const emit = defineEmits(['update:modelValue']);
</script>

<template>
  <div
    role="group"
    :aria-label="label"
    class="inline-flex gap-1 p-1 rounded-xl bg-n-alpha-2"
  >
    <button
      v-for="option in options"
      :key="option.value"
      type="button"
      :aria-pressed="option.value === modelValue"
      :disabled="disabled"
      :data-toggle="option.value"
      class="min-h-11 min-w-11 px-4 rounded-lg text-sm font-medium focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand disabled:opacity-60"
      :class="
        option.value === modelValue
          ? 'bg-n-solid-1 text-n-slate-12 shadow-sm'
          : 'text-n-slate-11 hover:text-n-slate-12'
      "
      @click="emit('update:modelValue', option.value)"
    >
      {{ option.label }}
    </button>
  </div>
</template>
