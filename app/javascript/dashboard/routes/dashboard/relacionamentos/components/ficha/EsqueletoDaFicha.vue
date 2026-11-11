<script setup>
import { useI18n } from 'vue-i18n';

// #2894 — "carregando" da ficha: a forma dela em cinza que pulsa (cabeçalho,
// coluna principal e coluna do lado), com o texto só para o leitor de tela.
const { t } = useI18n();
</script>

<template>
  <div
    data-relacionamentos="carregando"
    role="status"
    aria-busy="true"
    class="flex flex-col gap-6"
  >
    <span class="sr-only">{{ t('RELACIONAMENTOS.COMUM.CARREGANDO') }}</span>
    <div
      aria-hidden="true"
      class="h-48 rounded-2xl bg-n-alpha-2 animate-pulse"
    />
    <div aria-hidden="true" class="grid gap-6 lg:grid-cols-3">
      <div class="flex flex-col gap-6 lg:col-span-2">
        <div class="h-56 rounded-2xl bg-n-alpha-2 animate-pulse" />
        <div class="h-40 rounded-2xl bg-n-alpha-2 animate-pulse" />
      </div>
      <div class="flex flex-col gap-6">
        <div class="h-72 rounded-2xl bg-n-alpha-2 animate-pulse" />
        <div class="h-24 rounded-2xl bg-n-alpha-2 animate-pulse" />
      </div>
    </div>
  </div>
</template>
