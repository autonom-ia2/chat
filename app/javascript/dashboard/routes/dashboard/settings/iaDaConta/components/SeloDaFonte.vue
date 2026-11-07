<script setup>
import { computed } from 'vue';

// #2472: o estado de uma fonte em palavra simples, com cor e ponto.
const props = defineProps({
  status: { type: String, required: true },
});

const ESTILO = {
  funcionando: { chave: 'FUNCIONANDO', cor: 'bg-n-teal-3 text-n-teal-11' },
  reserva: { chave: 'RESERVA', cor: 'bg-n-slate-3 text-n-slate-11' },
  limite: { chave: 'LIMITE', cor: 'bg-n-amber-3 text-n-amber-11' },
  sem_credito: { chave: 'SEM_CREDITO', cor: 'bg-n-ruby-3 text-n-ruby-11' },
  desconectado: { chave: 'DESCONECTADO', cor: 'bg-n-ruby-3 text-n-ruby-11' },
  recusada: { chave: 'RECUSADA', cor: 'bg-n-ruby-3 text-n-ruby-11' },
};

const estilo = computed(() => ESTILO[props.status] || ESTILO.funcionando);
</script>

<template>
  <span
    data-selo
    class="inline-flex items-center gap-2 px-3 py-1 text-sm font-medium rounded-full"
    :class="estilo.cor"
  >
    <span class="rounded-full size-2 bg-current" aria-hidden="true" />
    {{ $t(`IA_DA_CONTA.SELO.${estilo.chave}`) }}
  </span>
</template>
