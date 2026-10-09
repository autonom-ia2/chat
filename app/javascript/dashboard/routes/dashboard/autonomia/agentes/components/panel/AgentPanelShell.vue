<script setup>
import { computed, nextTick, onMounted, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute } from 'vue-router';
import { useRouter } from 'vue-router';

import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import { useBranding } from 'shared/composables/useBranding';
import AgentSwitch from '../AgentSwitch.vue';
import AgentStatusPill from '../AgentStatusPill.vue';

const props = defineProps({
  agent: { type: Object, required: true },
  activeTab: { type: String, required: true },
  visibleTabs: { type: Array, required: true },
  canManage: { type: Boolean, default: false },
  isTogglingStatus: { type: Boolean, default: false },
  actionRoute: { type: Object, default: null },
  actionLabel: { type: String, default: '' },
});

const emit = defineEmits(['tabChange', 'toggle-status', 'back']);

const { t } = useI18n();
const route = useRoute();
const router = useRouter();
const { installationName } = useBranding();

const tabLabels = computed(() => ({
  performance: t('AGENTS.PANEL.REDESIGN_TABS.PERFORMANCE'),
  test: t('AGENTS.PANEL.REDESIGN_TABS.TEST'),
  knowledge: t('AGENTS.PANEL.REDESIGN_TABS.KNOWLEDGE'),
  channels: t('AGENTS.PANEL.REDESIGN_TABS.CHANNELS'),
  tune: t('AGENTS.PANEL.REDESIGN_TABS.TUNE'),
  tools: t('AGENTS.PANEL.REDESIGN_TABS.TOOLS'),
}));

const tabId = key => `agent-panel-tab-${key}`;
const panelId = key => `agent-panel-panel-${key}`;

const statusCode = computed(() => props.agent?.state?.code || 'E1');
const isLive = computed(() => ['E5', 'E6'].includes(statusCode.value));
const statusLabel = computed(() =>
  statusCode.value === 'E5'
    ? t('AGENTS.PANEL.REDESIGN_STATUS.ACTIVE')
    : t('AGENTS.PANEL.REDESIGN_STATUS.PAUSED')
);
const statusSwitchLabel = computed(() =>
  t('AGENTS.PANEL.REDESIGN_STATUS.TOGGLE_LABEL', {
    status: statusLabel.value,
    name: props.agent.name,
  })
);

const creationLabel = computed(
  () => props.actionLabel || t('AGENTS.PANEL.REDESIGN_ACTIONS.CONTINUE')
);
const isQuote = computed(() => props.agent?.agent_type === 'insurance_quote');
const quoteInstallationName = computed(
  () => installationName.value || 'Hub2You'
);

const goBack = () => emit('back');

const openAction = () => {
  if (props.actionRoute) router.push(props.actionRoute);
};

const selectTab = key => emit('tabChange', key);

const scrollTabIntoView = key => {
  const tab = document.getElementById(tabId(key));
  if (!tab) return;

  tab.scrollIntoView?.({ block: 'nearest', inline: 'nearest' });
};

const focusTab = key => {
  const tab = document.getElementById(tabId(key));
  if (!tab) return;

  // Keep the panel scroll position stable while making the roving tab visible.
  tab.focus({ preventScroll: true });
  scrollTabIntoView(key);
};

const revealActiveTab = () => {
  nextTick(() => scrollTabIntoView(props.activeTab));
};

onMounted(revealActiveTab);
watch([() => props.activeTab, () => route.fullPath], revealActiveTab);

const onTabKeydown = event => {
  const index = props.visibleTabs.indexOf(props.activeTab);
  if (index < 0 || !props.visibleTabs.length) return;

  let nextIndex = index;
  if (event.key === 'ArrowRight' || event.key === 'ArrowDown') {
    nextIndex = (index + 1) % props.visibleTabs.length;
  } else if (event.key === 'ArrowLeft' || event.key === 'ArrowUp') {
    nextIndex =
      (index - 1 + props.visibleTabs.length) % props.visibleTabs.length;
  } else if (event.key === 'Home') {
    nextIndex = 0;
  } else if (event.key === 'End') {
    nextIndex = props.visibleTabs.length - 1;
  } else {
    return;
  }

  event.preventDefault();
  const nextTab = props.visibleTabs[nextIndex];
  selectTab(nextTab);
  requestAnimationFrame(() => focusTab(nextTab));
};
</script>

<template>
  <main
    class="flex flex-col w-full h-full min-h-0 overflow-hidden bg-n-background"
    data-testid="agent-panel"
  >
    <header
      class="shrink-0 border-b border-n-weak bg-n-background"
      data-testid="agent-panel-header"
    >
      <div
        class="flex flex-col gap-4 px-4 py-4 mx-auto w-full max-w-7xl sm:px-6 lg:px-8"
      >
        <div class="flex flex-wrap items-start gap-3 sm:items-center">
          <button
            type="button"
            class="inline-flex items-center justify-center shrink-0 min-h-11 gap-1 px-2 rounded-lg text-n-slate-11 hover:bg-n-alpha-2 hover:text-n-slate-12 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
            :aria-label="t('AGENTS.PANEL.REDESIGN_ACTIONS.BACK')"
            data-action="back"
            @click="goBack"
          >
            <span class="i-lucide-arrow-left size-5" aria-hidden="true" />
            <span class="text-sm font-medium">
              {{ t('AGENTS.PANEL.REDESIGN_ACTIONS.BACK') }}
            </span>
          </button>
          <Avatar
            :name="agent.name"
            :src="agent.avatar_url"
            :size="64"
            class="shrink-0"
            data-testid="agent-panel-avatar"
          />
          <div class="min-w-0 grow">
            <div class="flex flex-wrap items-center gap-2">
              <h1 class="text-xl font-semibold truncate text-n-slate-12">
                {{ agent.name }}
              </h1>
              <AgentStatusPill
                :code="statusCode"
                data-testid="agent-panel-state"
              />
            </div>
            <p
              v-if="agent.human_card"
              class="max-w-3xl mt-1 text-sm leading-5 text-n-slate-11"
            >
              {{ agent.human_card }}
            </p>
          </div>
          <div
            class="flex items-center justify-end w-full gap-2 shrink-0 sm:ms-auto sm:w-auto"
          >
            <AgentSwitch
              v-if="canManage && isLive"
              class="hidden sm:inline-flex"
              :checked="statusCode === 'E5'"
              :disabled="isTogglingStatus"
              :aria-label="statusSwitchLabel"
              :label="statusLabel"
              data-action="toggle-status"
              :data-testid="`agent-panel-action-${
                statusCode === 'E5' ? 'pause' : 'activate'
              }`"
              @toggle="emit('toggle-status')"
            />
            <button
              v-if="actionRoute"
              type="button"
              class="inline-flex items-center justify-center min-h-11 gap-2 px-3 text-sm font-semibold rounded-lg bg-n-blue-11 text-white dark:text-n-navy hover:bg-n-blue-12 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
              data-action="continue-building"
              :data-testid="`agent-panel-action-${
                statusCode === 'E2m'
                  ? 'edit'
                  : statusCode === 'E4'
                    ? 'connect'
                    : 'continue'
              }`"
              @click="openAction"
            >
              <span class="i-lucide-pencil-line size-4" aria-hidden="true" />
              {{ creationLabel }}
            </button>
          </div>
        </div>
        <aside
          v-if="isQuote"
          class="flex flex-wrap items-start gap-2 p-3 text-sm leading-5 border rounded-lg border-n-amber-6 bg-n-amber-2 text-n-amber-12"
          role="note"
          data-state="quote-notice"
          data-testid="agent-quote-notice"
        >
          <span class="i-lucide-info size-4 shrink-0" aria-hidden="true" />
          <p class="min-w-0 grow">
            {{
              t('AGENTS.PANEL.REDESIGN_QUOTE_NOTICE', {
                name: agent.name,
                installationName: quoteInstallationName,
              })
            }}
            <router-link
              class="ms-1 font-semibold text-n-amber-12 underline hover:text-n-amber-12 hover:no-underline"
              :to="{
                name: 'autonomia_insurance',
                params: { accountId: route.params.accountId },
              }"
            >
              {{ t('AGENTS.PANEL.REDESIGN_QUOTE_LINK') }}
            </router-link>
          </p>
        </aside>
        <AgentSwitch
          v-if="canManage && isLive"
          class="inline-flex self-start sm:hidden"
          :checked="statusCode === 'E5'"
          :disabled="isTogglingStatus"
          :aria-label="statusSwitchLabel"
          :label="statusLabel"
          data-action="toggle-status-mobile"
          :data-testid="`agent-panel-action-mobile-${
            statusCode === 'E5' ? 'pause' : 'activate'
          }`"
          @toggle="emit('toggle-status')"
        />
        <div
          class="flex gap-1 overflow-x-auto border-b border-n-weak -mb-4"
          role="tablist"
          :aria-label="t('AGENTS.PANEL.REDESIGN_TABS.LABEL')"
          @keydown="onTabKeydown"
        >
          <button
            v-for="key in visibleTabs"
            :id="tabId(key)"
            :key="key"
            type="button"
            role="tab"
            :aria-selected="activeTab === key"
            :aria-controls="panelId(key)"
            :tabindex="activeTab === key ? 0 : -1"
            class="inline-flex min-h-12 shrink-0 items-center px-3 text-sm font-medium border-b-2 border-transparent text-n-slate-11 hover:text-n-slate-12 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
            :class="activeTab === key ? 'border-n-brand text-n-slate-12' : ''"
            @click="selectTab(key)"
          >
            {{ tabLabels[key] }}
          </button>
        </div>
      </div>
    </header>

    <div
      :id="panelId(activeTab)"
      class="min-h-0 flex-1 overflow-y-auto"
      role="tabpanel"
      :aria-labelledby="tabId(activeTab)"
      tabindex="0"
    >
      <slot />
    </div>
  </main>
</template>
