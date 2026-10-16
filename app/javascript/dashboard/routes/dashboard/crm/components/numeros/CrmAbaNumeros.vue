<script setup>
import { ROTA_NUMEROS, useAbaNumeros } from './useAbaNumeros';

// A quarta aba do seletor do CRM (#1617): leva à página Números. Mesmo desenho dos botões Kanban/Lista/Calendário.
const { mostrar } = useAbaNumeros();
</script>

<template>
  <RouterLink
    v-if="mostrar"
    :to="{ name: ROTA_NUMEROS }"
    data-aba-numeros
    class="inline-flex min-h-11 items-center gap-1.5 rounded-lg px-3 text-sm font-medium text-n-slate-11 transition-colors hover:bg-n-alpha-2 hover:text-n-slate-12 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand motion-reduce:transition-none"
  >
    <span class="i-lucide-chart-column size-3.5" aria-hidden="true" />
    {{ $t('FORK_SIDEBAR.CRM.ABA_NUMEROS') }}
  </RouterLink>
  <template v-else />
</template>
