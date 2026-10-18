<script setup>
import { reactive } from 'vue';
import TelaInicialResumo from './TelaInicialResumo.vue';
import { useTelaInicial } from './useTelaInicial';

// #1801 — a tela inicial da caixa de conversas; o EmptyState só a monta com a flag
// `tela_inicial_resumo` ligada na conta.
const dados = reactive(useTelaInicial());
</script>

<template>
  <TelaInicialResumo :dados="dados" />
</template>
