<script setup>
import { computed, defineAsyncComponent } from 'vue';
import { useAccount } from 'dashboard/composables/useAccount';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';

const { currentAccount } = useAccount();
const AgentsHubPage = defineAsyncComponent(() => import('./AgentsHubPage.vue'));
const AgentsListPage = defineAsyncComponent(
  () => import('../agentes/pages/AgentsListPage.vue')
);
const page = computed(() =>
  currentAccount.value?.autonomia_agents_redesign_enabled === true
    ? AgentsListPage
    : AgentsHubPage
);
</script>

<template>
  <Suspense>
    <component :is="page" :key="currentAccount.id" />
    <template #fallback><Spinner :size="28" /></template>
  </Suspense>
</template>
