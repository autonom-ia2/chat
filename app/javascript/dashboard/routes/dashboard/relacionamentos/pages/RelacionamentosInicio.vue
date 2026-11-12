<script setup>
import { computed, defineAsyncComponent } from 'vue';
import { useAccount } from 'dashboard/composables/useAccount';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import RelationshipsHome from '../../relationships/RelationshipsHome.vue';

// Carregada só quando a flag está ligada: a tela nova inteira não entra no
// pacote de quem ainda está com a flag desligada.
const ListaPage = defineAsyncComponent(() => import('./ListaPage.vue'));

// #2894 — a porta de Relacionamentos: com relacionamentos_novo ligada, a lista
// nova de pessoas e empresas; desligada, a página de hoje, sem mudança nenhuma.
// A aba Empresas é `?aba=empresas` nesta mesma rota.
const { isCloudFeatureEnabled } = useAccount();
const listaNova = computed(() =>
  isCloudFeatureEnabled(FEATURE_FLAGS.RELACIONAMENTOS_NOVO)
);
</script>

<template>
  <ListaPage v-if="listaNova" />
  <RelationshipsHome v-else />
</template>
