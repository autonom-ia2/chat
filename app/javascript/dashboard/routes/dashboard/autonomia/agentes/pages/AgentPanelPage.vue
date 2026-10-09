<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';

import { useAlert } from 'dashboard/composables';
import { useCanManage } from 'dashboard/composables/useCanManage';
import { useAccount } from 'dashboard/composables/useAccount';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import { CONVERSATION_PERMISSIONS } from 'dashboard/constants/permissions.js';
import {
  getUserPermissions,
  getUserRole,
} from 'dashboard/helper/permissionsHelper.js';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import ConfirmDialog from '../components/ConfirmDialog.vue';

import PanelWhereServes from '../components/panel/PanelWhereServes.vue';
import PanelKnows from '../components/panel/PanelKnows.vue';
import PanelAgentTest from '../components/panel/PanelAgentTest.vue';
import PanelToolsV2 from '../components/panel/PanelToolsV2.vue';
import PanelSettings from '../components/panel/PanelSettings.vue';
import AgentPanelShell from '../components/panel/AgentPanelShell.vue';
import PanelHowItsGoing from '../components/panel/PanelHowItsGoing.vue';
import PanelQuoteKnowledge from '../components/panel/PanelQuoteKnowledge.vue';

const props = defineProps({
  agentId: { type: [String, Number], required: true },
  tab: { type: String, default: 'performance' },
  resumeBuild: { type: Boolean, default: false },
});

const { t } = useI18n();
const router = useRouter();
const store = useStore();
const { currentAccount } = useAccount();
const canManage = useCanManage('autonomia_manage');
const currentUser = useMapGetter('getCurrentUser');
const uiFlags = useMapGetter('autonomiaAgents/getUIFlags');
const agent = computed(() =>
  store.getters['autonomiaAgents/getRecord'](Number(props.agentId))
);
const isReady = ref(false);
const loadError = ref(null);
const statusDialogRef = ref(null);
let entryVersion = 0;

const isSuperAdmin = computed(() => currentUser.value?.type === 'SuperAdmin');
const isInternal = computed(() => agent.value?.actuation === 'internal');
const isQuote = computed(() => agent.value?.agent_type === 'insurance_quote');
const stateCode = computed(() => agent.value?.state?.code || 'E1');
const canOpenConversation = computed(() => {
  const role = getUserRole(currentUser.value, currentAccount.value?.id);
  if (role === 'administrator') return true;
  const permissions = getUserPermissions(
    currentUser.value,
    currentAccount.value?.id
  );
  return CONVERSATION_PERMISSIONS.some(permission =>
    permissions.includes(permission)
  );
});

const tabOrder = [
  'performance',
  'test',
  'knowledge',
  'channels',
  'tune',
  'tools',
];
const viewTabs = ['performance', 'test'];

const visibleTabs = computed(() => {
  let tabs = [...tabOrder];
  if (isInternal.value) tabs = tabs.filter(tab => tab !== 'channels');
  if (isQuote.value) tabs = tabs.filter(tab => tab !== 'tools');
  if (!isSuperAdmin.value) tabs = tabs.filter(tab => tab !== 'tools');
  if (!canManage.value) tabs = tabs.filter(tab => viewTabs.includes(tab));
  return tabs;
});

const activeTab = computed(() =>
  visibleTabs.value.includes(props.tab) ? props.tab : 'performance'
);

const activeComponent = computed(() => {
  switch (activeTab.value) {
    case 'test':
      return PanelAgentTest;
    case 'knowledge':
      return isQuote.value ? PanelQuoteKnowledge : PanelKnows;
    case 'channels':
      return PanelWhereServes;
    case 'tune':
      return PanelSettings;
    case 'tools':
      return PanelToolsV2;
    default:
      return PanelHowItsGoing;
  }
});

const activeProps = computed(() => {
  const base = { agentId: Number(props.agentId), agent: agent.value };
  if (activeTab.value === 'performance') {
    return { ...base, canOpenConversation: canOpenConversation.value };
  }
  if (activeTab.value === 'tune')
    return { ...base, resumeBuild: props.resumeBuild };
  if (activeTab.value === 'knowledge' && isQuote.value) {
    return { agent: agent.value };
  }
  return base;
});

const actionRoute = computed(() => {
  if (!agent.value?.id) return null;
  const stepByState = {
    E1: 'tell',
    E2: 'tell',
    E2m: 'tune',
    E3: 'test',
    E4: 'live',
  };
  const step = stepByState[stateCode.value];
  if (!step || !canManage.value) return null;
  return {
    name: step === 'tune' ? 'autonomia_agent_panel' : 'autonomia_agent_build',
    params:
      step === 'tune'
        ? { agentId: props.agentId, tab: 'tune' }
        : { agentId: props.agentId, step },
  };
});

const actionLabel = computed(() => {
  if (stateCode.value === 'E4')
    return t('AGENTS.PANEL.REDESIGN_ACTIONS.CONNECT');
  if (['E1', 'E2', 'E3'].includes(stateCode.value))
    return t('AGENTS.PANEL.REDESIGN_ACTIONS.CONTINUE');
  return t('AGENTS.PANEL.REDESIGN_ACTIONS.EDIT');
});

const redirectForbiddenTab = () => {
  if (props.tab === activeTab.value) return;
  router.replace({
    name: 'autonomia_agent_panel',
    params: { agentId: props.agentId, tab: activeTab.value },
  });
};

const onTabChange = tab => {
  if (!visibleTabs.value.includes(tab) || tab === props.tab) return;
  router.push({
    name: 'autonomia_agent_panel',
    params: { agentId: props.agentId, tab },
  });
};

const onBack = () =>
  router.push({
    name: 'autonomia_agents_index',
    params: { accountId: currentAccount.value?.id },
  });

const updateStatus = async (status, enabled) => {
  if (!agent.value?.id || !canManage.value) return;
  try {
    await store.dispatch('autonomiaAgents/update', {
      id: Number(props.agentId),
      status,
      enabled,
    });
    statusDialogRef.value?.close();
    useAlert(
      t(
        status === 'paused'
          ? 'AGENTS.PANEL.STATUS_CONTROL.PAUSED'
          : 'AGENTS.PANEL.STATUS_CONTROL.ACTIVATED'
      )
    );
  } catch (error) {
    useAlert(t('AGENTS.PANEL.STATUS_CONTROL.ERROR'));
  }
};

const requestToggleStatus = () => {
  if (!agent.value?.id || !canManage.value) return;
  if (stateCode.value === 'E5') {
    statusDialogRef.value?.open();
    return;
  }
  if (stateCode.value === 'E6') updateStatus('active', true);
};

const continueCreation = () => {
  if (actionRoute.value) router.push(actionRoute.value);
};

const refreshAgent = () =>
  store.dispatch('autonomiaAgents/show', Number(props.agentId));

const confirmPause = () => updateStatus('paused', false);

watch(
  [() => props.agentId, () => props.resumeBuild],
  async () => {
    entryVersion += 1;
    const version = entryVersion;
    isReady.value = false;
    loadError.value = null;
    try {
      await store.dispatch('autonomiaAgents/show', Number(props.agentId));
      if (version !== entryVersion) return;
      if (version === entryVersion) isReady.value = true;
    } catch (error) {
      if (version !== entryVersion) return;
      loadError.value = error;
      router.replace({ name: 'autonomia_agents_index' });
    }
  },
  { immediate: true }
);

watch([visibleTabs, () => props.tab], redirectForbiddenTab, {
  immediate: true,
});
</script>

<template>
  <div v-if="!isReady" class="flex items-center justify-center w-full h-full">
    <div
      v-if="loadError"
      class="grid gap-3 max-w-sm px-6 text-center"
      role="alert"
    >
      <p class="text-sm text-n-ruby-11">{{ t('AGENTS.PANEL.ERROR') }}</p>
      <button
        type="button"
        class="inline-flex items-center justify-center min-h-11 px-4 text-sm font-semibold rounded-lg border border-n-weak text-n-slate-12 hover:border-n-brand focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
        @click="router.go(0)"
      >
        {{ t('AGENTS.PERFORMANCE.RETRY') }}
      </button>
    </div>
    <Spinner v-else :size="28" :aria-label="t('AGENTS.PANEL.LOADING')" />
  </div>
  <AgentPanelShell
    v-else-if="agent"
    :agent="agent"
    :active-tab="activeTab"
    :visible-tabs="visibleTabs"
    :can-manage="canManage"
    :is-toggling-status="uiFlags.updatingItem"
    :action-route="actionRoute"
    :action-label="actionLabel"
    @back="onBack"
    @tab-change="onTabChange"
    @toggle-status="requestToggleStatus"
  >
    <component
      :is="activeComponent"
      :key="`${props.agentId}-${activeTab}`"
      v-bind="activeProps"
      :can-manage="canManage"
      @changed="refreshAgent"
      @updated="refreshAgent"
      @agentUpdated="refreshAgent"
      @continue="continueCreation"
      @deleted="onBack"
      @teach="onTabChange('knowledge')"
    />
    <ConfirmDialog
      ref="statusDialogRef"
      :title="t('AGENTS.V2.dialog.pauseTitle')"
      :description="
        t(
          isInternal
            ? 'AGENTS.V2.dialog.pauseInternalDescription'
            : 'AGENTS.V2.dialog.pauseDescription',
          { name: agent.name }
        )
      "
      :confirm-label="t('AGENTS.V2.actions.pause')"
      :cancel-label="t('AGENTS.V2.actions.cancel')"
      :is-loading="uiFlags.updatingItem"
      @confirm="confirmPause"
    />
  </AgentPanelShell>
</template>
