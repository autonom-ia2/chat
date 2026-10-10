<script setup>
// Botão de ligar/desligar (dia da semana, pessoa, duração extra): o leitor de
// tela ouve "pressionado" pelo aria-pressed, e o alvo tem 44 px.
defineProps({
  pressed: { type: Boolean, default: false },
  label: { type: String, required: true },
  // Nome completo para o leitor de tela quando o rótulo visível é curto (Seg).
  ariaLabel: { type: String, default: '' },
  disabled: { type: Boolean, default: false },
});

const emit = defineEmits(['toggle']);
</script>

<template>
  <button
    type="button"
    :aria-pressed="pressed ? 'true' : 'false'"
    :aria-label="ariaLabel || undefined"
    :disabled="disabled"
    class="inline-flex items-center justify-center gap-2 min-h-11 min-w-11 px-4 rounded-xl text-base font-medium transition ring-1 ring-inset focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand disabled:cursor-not-allowed disabled:opacity-60"
    :class="
      pressed
        ? 'bg-n-blue-9 text-white ring-n-blue-9'
        : 'bg-n-solid-1 text-n-slate-12 ring-n-weak hover:ring-n-blue-7'
    "
    @click="emit('toggle')"
  >
    <span
      v-if="pressed"
      class="i-lucide-check size-4 shrink-0"
      aria-hidden="true"
    />
    {{ label }}
  </button>
</template>
