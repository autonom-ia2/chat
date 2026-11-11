<script setup>
import { useI18n } from 'vue-i18n';

// #2894 — "carregando" das listas: linhas cinzas que pulsam, com o texto só
// para o leitor de tela.
defineProps({
  linhas: { type: Number, default: 6 },
});

const { t } = useI18n();
</script>

<template>
  <div
    data-esqueleto
    role="status"
    aria-busy="true"
    class="flex flex-col gap-3"
  >
    <span class="sr-only">{{ t('RELACIONAMENTOS.COMUM.CARREGANDO') }}</span>
    <div
      v-for="linha in linhas"
      :key="linha"
      aria-hidden="true"
      class="h-16 rounded-2xl bg-n-alpha-2 animate-pulse"
    />
  </div>
</template>
