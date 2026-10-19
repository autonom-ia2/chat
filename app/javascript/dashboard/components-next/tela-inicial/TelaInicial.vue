<script setup>
import { computed, reactive } from 'vue';
import { isCrmKanbanEnabled } from 'dashboard/helper/routeHelpers';
import { useQuemVeNumeros } from 'dashboard/routes/dashboard/crm/components/numeros/useQuemVeNumeros';
import TelaInicialResumo from './TelaInicialResumo.vue';
import { useTelaInicial } from './useTelaInicial';

// #1801 — a tela inicial da caixa de conversas; o EmptyState só a monta com a flag
// `tela_inicial_resumo` ligada na conta.
const dados = reactive(useTelaInicial());

// #1897: com CRM › Números por papel, o rodapé "Como vai o seu mês →" para quem abre
// Números, já na visão "Só eu" quando ela existe. Sem número: o mês fica em Números.
const { ligado, veSoEu, abreNumeros } = useQuemVeNumeros();
const comoVaiOMes = computed(() => {
  if (!ligado.value || !abreNumeros.value || !isCrmKanbanEnabled()) return null;
  return {
    name: 'crm_dashboard_index',
    query: veSoEu.value ? { visao: 'eu' } : {},
  };
});
</script>

<template>
  <TelaInicialResumo :dados="dados" :como-vai-o-mes="comoVaiOMes" />
</template>
