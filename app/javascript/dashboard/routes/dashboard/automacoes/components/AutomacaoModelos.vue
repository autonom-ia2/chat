<script setup>
import { MODELOS } from '../modelos';

defineProps({
  desabilitado: { type: Boolean, default: false },
});

const emit = defineEmits(['escolher']);
</script>

<template>
  <ul class="grid gap-3 sm:grid-cols-3">
    <li v-for="modelo in MODELOS" :key="modelo.chave">
      <button
        type="button"
        :data-modelo="modelo.chave"
        :disabled="desabilitado"
        class="flex flex-col items-start gap-2 w-full h-full min-h-11 p-4 text-start rounded-xl border border-n-weak bg-n-solid-1 hover:bg-n-alpha-1 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand transition-colors disabled:cursor-not-allowed disabled:opacity-60"
        @click="emit('escolher', modelo.chave)"
      >
        <span
          class="size-5 text-n-brand"
          :class="modelo.icone"
          aria-hidden="true"
        />
        <span class="text-sm font-medium text-n-slate-12">
          {{ $t(`AUTOMACOES.MODELOS.${modelo.chave}.TITULO`) }}
        </span>
        <span class="text-sm text-n-slate-11">
          {{ $t(`AUTOMACOES.MODELOS.${modelo.chave}.TEXTO`) }}
        </span>
      </button>
    </li>
  </ul>
</template>
