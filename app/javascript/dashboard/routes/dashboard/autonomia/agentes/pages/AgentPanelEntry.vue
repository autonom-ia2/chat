<script setup>
import { computed, defineAsyncComponent } from 'vue';
import { useAccount } from 'dashboard/composables/useAccount';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';

defineProps({
  agentId: { type: [String, Number], required: true },
  tab: { type: String, default: 'performance' },
  resumeBuild: { type: Boolean, default: false },
});

const { currentAccount } = useAccount();
const LegacyAgentPanelPage = defineAsyncComponent(
  () => import('../../pages/AgentPanelPage.vue')
);
const RedesignAgentPanelPage = defineAsyncComponent(
  () => import('./AgentPanelPage.vue')
);

const isRedesignEnabled = computed(
  () => currentAccount.value?.autonomia_agents_redesign_enabled === true
);

const page = computed(() =>
  isRedesignEnabled.value ? RedesignAgentPanelPage : LegacyAgentPanelPage
);
</script>

<template>
  <Suspense>
    <component
      :is="page"
      :key="`${currentAccount?.id}-${isRedesignEnabled}`"
      :agent-id="agentId"
      :tab="tab"
      :resume-build="resumeBuild"
    />
    <template #fallback>
      <div class="flex items-center justify-center w-full h-full">
        <Spinner :size="28" />
      </div>
    </template>
  </Suspense>
</template>
