<script setup>
import { computed, defineAsyncComponent } from 'vue';
import { useAccount } from 'dashboard/composables/useAccount';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';

const props = defineProps({
  agentId: { type: [String, Number], default: null },
  step: { type: String, default: 'choice' },
});
const { currentAccount } = useAccount();
const AgentCreationPage = defineAsyncComponent(
  () => import('./AgentCreationPage.vue')
);
const AgentBuilderPage = defineAsyncComponent(
  () => import('../../pages/AgentBuilderPage.vue')
);
const AgentPanelPage = defineAsyncComponent(
  () => import('../../pages/AgentPanelPage.vue')
);
const redesignEnabled = computed(
  () => currentAccount.value?.autonomia_agents_redesign_enabled === true
);
const page = computed(() => {
  if (redesignEnabled.value) return AgentCreationPage;
  return props.step === 'choice' ? AgentBuilderPage : AgentPanelPage;
});
const pageProps = computed(() => {
  if (redesignEnabled.value) {
    return {
      agentId: props.agentId,
      step: props.step,
    };
  }
  if (props.step === 'choice') return {};
  return {
    agentId: props.agentId,
    tab: { tell: 'tune', test: 'test', live: 'publish', ready: 'performance' }[
      props.step
    ],
    resumeBuild: true,
  };
});
</script>

<template>
  <Suspense>
    <component
      :is="page"
      :key="`${currentAccount.id}-${redesignEnabled}`"
      v-bind="pageProps"
    />
    <template #fallback><Spinner :size="28" /></template>
  </Suspense>
</template>
