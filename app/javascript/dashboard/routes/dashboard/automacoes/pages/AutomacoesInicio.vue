<script setup>
import { computed } from 'vue';
import { useAccount } from 'dashboard/composables/useAccount';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import AutomacoesPage from './AutomacoesPage.vue';
import LivreListaPage from '../livre/pages/LivreListaPage.vue';

// #2414 F5 — a porta de Automações: com automacao_editor ligada, a lista única
// (novas e do jeito antigo); desligada, a lista de hoje, sem mudança nenhuma.
const { isCloudFeatureEnabled } = useAccount();
const listaUnica = computed(() =>
  isCloudFeatureEnabled(FEATURE_FLAGS.AUTOMACAO_EDITOR)
);
</script>

<template>
  <LivreListaPage v-if="listaUnica" />
  <AutomacoesPage v-else />
</template>
