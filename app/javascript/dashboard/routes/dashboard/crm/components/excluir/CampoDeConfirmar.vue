<script setup>
import { useId } from 'vue';

// O campo "Para confirmar, digite ..." das janelas de excluir de vez (#2096). Sem corretor nem preenchimento
// automático: a pessoa digita de propósito.
defineProps({
  rotulo: { type: String, required: true },
  dica: { type: String, default: '' },
  desabilitado: { type: Boolean, default: false },
});
const valor = defineModel({ type: String, default: '' });
const id = useId();
</script>

<template>
  <div class="flex flex-col gap-1.5">
    <label :for="id" class="mb-0 text-sm font-medium text-n-slate-12">
      {{ rotulo }}
    </label>
    <input
      :id="id"
      v-model="valor"
      data-campo-confirmar
      type="text"
      autocomplete="off"
      autocapitalize="off"
      spellcheck="false"
      :placeholder="dica"
      :disabled="desabilitado"
      class="!mb-0 min-h-11 w-full rounded-lg border border-n-weak bg-n-alpha-black2 px-3 text-sm text-n-slate-12 outline-none focus:border-n-brand focus:ring-1 focus:ring-n-brand disabled:opacity-60"
    />
  </div>
</template>
