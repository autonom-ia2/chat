<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';

import { useCanManage } from 'dashboard/composables/useCanManage';
import NoticeBanner from '../components/NoticeBanner.vue';
import AgentRow from '../components/AgentRow.vue';
import AgentsEmptyHero from '../components/AgentsEmptyHero.vue';
import AgentsSummaryChips from '../components/AgentsSummaryChips.vue';
import { useAgentsList } from '../composables/useAgentsList';

const { t } = useI18n();
const router = useRouter();
const canManage = useCanManage('autonomia_manage');
const list = useAgentsList();
const {
  rows,
  status,
  isLoading,
  isStale,
  load,
  retry,
  updateStatus,
  deleteDraft: removeDraft,
} = list;

const actionError = ref(null);
const activeAction = ref(null);

const hasRows = computed(() => rows.value.length > 0);
const showSkeleton = computed(() => isLoading.value && !hasRows.value);
const showEmpty = computed(() => status.value === 'success' && !hasRows.value);
const showInitialError = computed(
  () => status.value === 'error' && !hasRows.value
);

const routeToPanel = (agent, tab = 'performance') =>
  router.push({
    name: 'autonomia_agent_panel',
    params: { agentId: agent.id, tab },
  });

const openAgent = agent => routeToPanel(agent);

const continueAgent = agent => {
  const code = agent.state?.code;
  actionError.value = null;

  if (code === 'E2m') {
    router.push({
      name: 'autonomia_agent_panel_legacy',
      params: { agentId: agent.id, tab: 'tune' },
    });
    return;
  }

  if (code === 'E1' || code === 'E2') {
    router.push({
      name: 'autonomia_agent_build',
      params: { agentId: agent.id, step: 'tell' },
    });
    return;
  }

  if (code === 'E3') {
    router.push({
      name: 'autonomia_agent_build',
      params: { agentId: agent.id, step: 'test' },
    });
    return;
  }

  if (code === 'E4') {
    router.push({
      name: 'autonomia_agent_build',
      params: { agentId: agent.id, step: 'live' },
    });
  }
};

const createAgent = () => router.push({ name: 'autonomia_agents_builder' });

const selectModel = modelId =>
  router.push({
    name: 'autonomia_agents_builder',
    query: { type: modelId },
  });

const toggleStatus = async (agent, change) => {
  actionError.value = null;
  activeAction.value = agent.id;
  try {
    await updateStatus(agent, change);
  } catch {
    actionError.value = t('AGENTS.V2.errors.update');
  } finally {
    activeAction.value = null;
  }
};

const deleteDraft = async agent => {
  actionError.value = null;
  activeAction.value = agent.id;
  try {
    await removeDraft(agent);
  } catch {
    actionError.value = t('AGENTS.V2.errors.delete');
  } finally {
    activeAction.value = null;
  }
};

onMounted(() => load());
</script>

<template>
  <main
    class="flex h-full min-h-0 w-full flex-col overflow-hidden bg-n-background"
  >
    <header v-if="!showEmpty" class="shrink-0 border-b border-n-weak">
      <div
        class="mx-auto flex w-full max-w-6xl flex-col gap-4 px-4 py-6 sm:flex-row sm:items-center sm:justify-between sm:px-6 sm:py-8"
      >
        <div class="min-w-0">
          <h1
            class="text-3xl font-semibold leading-tight tracking-tight text-n-slate-12 sm:text-4xl"
          >
            {{ t('AGENTS.V2.list.title') }}
          </h1>
          <p class="mt-2 max-w-2xl text-base leading-relaxed text-n-slate-11">
            {{ t('AGENTS.V2.list.description') }}
          </p>
        </div>
        <button
          v-if="canManage"
          type="button"
          class="inline-flex min-h-11 shrink-0 items-center justify-center gap-2 rounded-lg bg-n-blue-11 px-4 text-sm font-semibold text-white dark:text-n-navy hover:bg-n-blue-12 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
          data-create-agent
          @click="createAgent"
        >
          <span class="i-lucide-plus size-4" aria-hidden="true" />
          {{ t('AGENTS.V2.actions.create') }}
        </button>
      </div>
    </header>

    <div class="min-h-0 flex-1 overflow-y-auto">
      <div
        v-if="showSkeleton"
        class="grid gap-4 px-4 py-5 sm:px-6"
        aria-busy="true"
        :aria-label="t('AGENTS.V2.list.loading')"
      >
        <span class="sr-only">{{ t('AGENTS.V2.list.loading') }}</span>
        <div class="h-9 w-72 animate-pulse rounded-full bg-n-solid-3" />
        <div
          v-for="item in 3"
          :key="item"
          class="h-32 animate-pulse rounded-xl bg-n-solid-3"
        />
      </div>

      <div
        v-else-if="showInitialError"
        class="grid place-items-center px-4 py-16 text-center sm:px-6"
        role="alert"
      >
        <div class="max-w-md">
          <span
            class="mx-auto flex size-12 items-center justify-center rounded-xl bg-n-ruby-3 text-n-ruby-11"
            aria-hidden="true"
          >
            <span class="i-lucide-cloud-off size-6" />
          </span>
          <h2 class="mt-4 text-lg font-semibold text-n-slate-12">
            {{ t('AGENTS.V2.errors.loadTitle') }}
          </h2>
          <p class="mt-2 text-sm leading-relaxed text-n-slate-11">
            {{ t('AGENTS.V2.errors.loadDescription') }}
          </p>
          <button
            type="button"
            class="mt-5 inline-flex min-h-11 items-center justify-center gap-2 rounded-lg border border-n-weak px-4 text-sm font-semibold text-n-slate-12 hover:border-n-brand focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
            data-action="retry"
            @click="retry"
          >
            <span class="i-lucide-refresh-cw size-4" aria-hidden="true" />
            {{ t('AGENTS.V2.actions.retry') }}
          </button>
        </div>
      </div>

      <div
        v-else
        class="mx-auto grid w-full max-w-6xl gap-5 px-4 pt-5 pb-24 sm:px-6 sm:pt-7 md:pb-7"
      >
        <NoticeBanner v-if="actionError" tone="ruby">
          <span>{{ actionError }}</span>
        </NoticeBanner>
        <NoticeBanner v-if="isStale" tone="amber">
          <span>{{ t('AGENTS.V2.errors.stale') }}</span>
        </NoticeBanner>
        <NoticeBanner v-if="hasRows && status === 'error'" tone="amber">
          <span>{{ t('AGENTS.V2.errors.refresh') }}</span>
          <button
            type="button"
            class="ms-2 min-h-11 rounded-md px-2 font-semibold underline focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
            data-action="retry"
            @click="retry"
          >
            {{ t('AGENTS.V2.actions.retry') }}
          </button>
        </NoticeBanner>

        <AgentsEmptyHero
          v-if="showEmpty"
          :can-manage="canManage"
          @create="createAgent"
          @select-model="selectModel"
        />

        <template v-else>
          <AgentsSummaryChips :agents="rows" />
          <section
            class="grid gap-3"
            :aria-label="t('AGENTS.V2.list.ariaLabel')"
          >
            <AgentRow
              v-for="agent in rows"
              :key="agent.id"
              :agent="agent"
              :can-manage="canManage"
              :busy="activeAction === agent.id"
              @open="openAgent"
              @continue="continueAgent"
              @toggle-status="change => toggleStatus(agent, change)"
              @delete="deleteDraft"
            />
          </section>
          <p
            v-if="!canManage"
            class="flex items-start gap-2 rounded-lg bg-n-solid-2 p-3 text-sm leading-relaxed text-n-slate-11"
          >
            <span
              class="i-lucide-lock mt-0.5 size-4 shrink-0"
              aria-hidden="true"
            />
            {{ t('AGENTS.V2.list.viewerHint') }}
          </p>
          <NoticeBanner v-if="hasRows" tone="slate" data-pause-notice>
            <span>{{ t('AGENTS.V2.list.pauseNotice') }}</span>
          </NoticeBanner>
        </template>
      </div>
    </div>
  </main>
</template>
