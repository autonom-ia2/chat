<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';

import AutonomiaSourcesAPI from 'dashboard/api/autonomia/sources';
import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import {
  isAbortError,
  useAbortableRequest,
} from 'dashboard/composables/useAbortableRequest';
import KnowledgeMaterialCard from './KnowledgeMaterialCard.vue';
import AddMaterialDialog from './AddMaterialDialog.vue';
import FaqReviewList from './FaqReviewList.vue';

const props = defineProps({
  agentId: { type: Number, required: true },
  agent: { type: Object, required: true },
  canManage: { type: Boolean, default: false },
});

const emit = defineEmits(['updated']);

const MAX_KNOWLEDGE_SOURCES = 30;

const { t } = useI18n();
const { run } = useAbortableRequest();

const sources = ref([]);
const state = ref('idle');
const writeError = ref('');
const resyncingId = ref(null);
const removingId = ref(null);
const sourceToRemove = ref(null);
const addDialog = ref(null);
const removeDialog = ref(null);

const knowledgeSources = computed(() =>
  sources.value.filter(source => source.kind === 'knowledge')
);
const count = computed(() => knowledgeSources.value.length);
const atLimit = computed(() => count.value >= MAX_KNOWLEDGE_SOURCES);
const knowledgeConfidence = computed(() => {
  const value = Number(props.agent.config?.knowledge_confidence);
  if (!Number.isFinite(value)) return 0;
  return Math.max(0, Math.min(1, value));
});
const knowledgeConfidencePercent = computed(() =>
  Math.round(knowledgeConfidence.value * 100)
);
const knowledgeConfidenceQuality = computed(() => {
  if (knowledgeConfidencePercent.value >= 70) {
    return t('AGENTS.PANEL.REDESIGN_KNOWLEDGE.CONFIDENCE_QUALITY.GOOD');
  }
  if (knowledgeConfidencePercent.value >= 40) {
    return t('AGENTS.PANEL.REDESIGN_KNOWLEDGE.CONFIDENCE_QUALITY.FAIR');
  }
  return t('AGENTS.PANEL.REDESIGN_KNOWLEDGE.CONFIDENCE_QUALITY.WEAK');
});
const knowledgeConfidenceText = computed(() =>
  t('AGENTS.PANEL.REDESIGN_KNOWLEDGE.CONFIDENCE_VALUE', {
    confidence: knowledgeConfidencePercent.value,
    quality: knowledgeConfidenceQuality.value,
  })
);
const agentName = computed(
  () => props.agent.name || t('AGENTS.PANEL.REDESIGN_KNOWLEDGE.AGENT')
);
const writeErrorMessage = computed(() => {
  if (writeError.value === 'AGENTS.PANEL.REDESIGN_KNOWLEDGE.RESYNC_ERROR') {
    return t('AGENTS.PANEL.REDESIGN_KNOWLEDGE.RESYNC_ERROR');
  }
  if (writeError.value === 'AGENTS.PANEL.REDESIGN_KNOWLEDGE.REMOVE_ERROR') {
    return t('AGENTS.PANEL.REDESIGN_KNOWLEDGE.REMOVE_ERROR');
  }
  return '';
});

const loadSources = async () => {
  state.value = 'loading';
  writeError.value = '';

  try {
    const response = await run(signal =>
      AutonomiaSourcesAPI.get(props.agentId, { signal })
    );
    if (!response) return;
    sources.value = response.data.payload;
    state.value = 'ready';
  } catch (requestError) {
    if (isAbortError(requestError)) return;
    state.value = 'error';
  }
};

watch(() => props.agentId, loadSources, { immediate: true });

const retry = () => loadSources();
const openAdd = () => {
  if (!props.canManage || atLimit.value) return;
  addDialog.value?.open();
};
const refreshAfterWrite = async () => {
  await loadSources();
  emit('updated');
};

const resync = async sourceId => {
  if (!props.canManage || resyncingId.value) return;
  resyncingId.value = sourceId;
  writeError.value = '';
  try {
    await AutonomiaSourcesAPI.resync(props.agentId, sourceId);
    await refreshAfterWrite();
  } catch {
    writeError.value = 'AGENTS.PANEL.REDESIGN_KNOWLEDGE.RESYNC_ERROR';
  } finally {
    resyncingId.value = null;
  }
};

const askRemove = sourceId => {
  if (!props.canManage) return;
  sourceToRemove.value = knowledgeSources.value.find(
    source => source.id === sourceId
  );
  removeDialog.value?.open();
};

const remove = async () => {
  if (!sourceToRemove.value || removingId.value) return;
  const { id } = sourceToRemove.value;
  removingId.value = id;
  writeError.value = '';
  try {
    await AutonomiaSourcesAPI.delete(props.agentId, id);
    sourceToRemove.value = null;
    removeDialog.value?.close();
    await refreshAfterWrite();
  } catch {
    writeError.value = 'AGENTS.PANEL.REDESIGN_KNOWLEDGE.REMOVE_ERROR';
  } finally {
    removingId.value = null;
  }
};

const handleAdded = () => refreshAfterWrite();
</script>

<template>
  <section
    class="flex flex-col w-full max-w-4xl gap-5 px-4 py-6 mx-auto sm:px-6 lg:px-8"
    data-testid="agent-panel-knows"
  >
    <div
      class="flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between"
    >
      <div class="min-w-0">
        <h2 class="m-0 text-xl font-semibold text-n-slate-12">
          {{ t('AGENTS.PANEL.REDESIGN_KNOWLEDGE.TITLE') }}
        </h2>
        <p class="mt-1 mb-0 text-sm leading-5 text-n-slate-11">
          {{
            t('AGENTS.PANEL.REDESIGN_KNOWLEDGE.DESCRIPTION', {
              name: agentName,
            })
          }}
        </p>
      </div>
      <Button
        v-if="canManage"
        solid
        size="md"
        icon="i-lucide-plus"
        class="min-h-11 shrink-0 !bg-n-blue-11 !text-white dark:!text-n-navy hover:enabled:!bg-n-blue-12 hover:enabled:!brightness-100 focus-visible:!brightness-100 focus-visible:!outline-n-blue-11"
        :label="t('AGENTS.PANEL.REDESIGN_KNOWLEDGE.ADD')"
        :disabled="atLimit"
        data-action="add-material"
        @click="openAdd"
      />
    </div>

    <div
      v-if="writeErrorMessage"
      class="flex items-center justify-between gap-3 p-3 text-sm rounded-lg bg-n-ruby-9/10 text-n-ruby-11"
      role="alert"
    >
      <span>{{ writeErrorMessage }}</span>
      <Button
        ghost
        ruby
        size="sm"
        class="min-h-11"
        :label="t('AGENTS.PANEL.REDESIGN_KNOWLEDGE.RETRY')"
        @click="loadSources"
      />
    </div>

    <div
      v-if="state === 'loading'"
      class="flex items-center justify-center py-12"
      role="status"
    >
      <span
        class="i-lucide-loader-circle size-6 animate-spin text-n-slate-11"
        aria-hidden="true"
      />
      <span class="sr-only">{{
        t('AGENTS.PANEL.REDESIGN_KNOWLEDGE.LOADING')
      }}</span>
    </div>

    <div
      v-else-if="state === 'error'"
      class="flex flex-col items-start gap-3"
      data-state="error"
      role="alert"
    >
      <p class="m-0 text-sm text-n-ruby-11">
        {{ t('AGENTS.PANEL.REDESIGN_KNOWLEDGE.ERROR') }}
      </p>
      <Button
        outline
        ruby
        size="sm"
        class="min-h-11"
        :label="t('AGENTS.PANEL.REDESIGN_KNOWLEDGE.RETRY')"
        data-action="retry-sources"
        @click="retry"
      />
    </div>

    <template v-else>
      <div
        class="flex flex-col gap-2 p-4 border rounded-xl border-n-weak bg-n-alpha-1"
      >
        <div class="flex items-center justify-between gap-3">
          <h3 class="m-0 text-sm font-medium text-n-slate-12">
            {{ t('AGENTS.PANEL.REDESIGN_KNOWLEDGE.BASE_TITLE') }}
          </h3>
          <span
            class="text-xs font-medium text-n-slate-11"
            data-testid="knowledge-confidence"
          >
            {{ knowledgeConfidenceText }}
          </span>
        </div>
        <div
          class="h-2 overflow-hidden rounded-full bg-n-slate-4"
          role="progressbar"
          :aria-label="t('AGENTS.PANEL.REDESIGN_KNOWLEDGE.CONFIDENCE_LABEL')"
          :aria-valuenow="Math.round(knowledgeConfidence * 100)"
          aria-valuemin="0"
          aria-valuemax="100"
        >
          <svg
            class="h-full w-full text-n-teal-9"
            viewBox="0 0 100 1"
            preserveAspectRatio="none"
            aria-hidden="true"
          >
            <rect
              :width="knowledgeConfidence * 100"
              height="1"
              fill="currentColor"
            />
          </svg>
        </div>
        <div
          class="flex flex-wrap items-baseline justify-between gap-x-3 gap-y-1"
        >
          <span
            class="text-xs font-medium text-n-slate-11"
            data-testid="knowledge-count"
          >
            {{
              t('AGENTS.PANEL.REDESIGN_KNOWLEDGE.COUNT', {
                count,
                limit: MAX_KNOWLEDGE_SOURCES,
              })
            }}
          </span>
          <p class="m-0 text-xs text-n-slate-11">
            {{ t('AGENTS.PANEL.REDESIGN_KNOWLEDGE.BASE_HINT') }}
          </p>
        </div>
      </div>

      <div
        v-if="atLimit"
        class="flex items-start gap-2 p-3 text-sm rounded-lg bg-n-amber-3 text-n-amber-12"
        data-testid="knowledge-limit"
      >
        <i class="i-lucide-info size-4 mt-0.5 shrink-0" aria-hidden="true" />
        <span>{{ t('AGENTS.PANEL.REDESIGN_KNOWLEDGE.LIMIT') }}</span>
      </div>

      <div
        v-if="!knowledgeSources.length"
        class="px-5 py-8 text-sm leading-6 text-center border border-dashed rounded-xl border-n-weak text-n-slate-11"
        data-state="empty"
      >
        {{ t('AGENTS.PANEL.REDESIGN_KNOWLEDGE.EMPTY', { name: agentName }) }}
      </div>

      <ul v-else class="list-none grid min-w-0 gap-3">
        <li v-for="source in knowledgeSources" :key="source.id" class="min-w-0">
          <KnowledgeMaterialCard
            :source="source"
            :can-manage="canManage"
            :resyncing="resyncingId === source.id"
            :removing="removingId === source.id"
            @resync="resync"
            @remove="askRemove"
          />
        </li>
      </ul>

      <FaqReviewList
        v-if="canManage && agent.agent_type !== 'insurance_quote'"
        :agent-id="agentId"
        :agent="agent"
        :can-manage="canManage"
        @approved="handleAdded"
        @updated="emit('updated')"
      />
    </template>

    <AddMaterialDialog
      v-if="canManage"
      ref="addDialog"
      :agent-id="agentId"
      :disabled="atLimit"
      @added="handleAdded"
    />

    <Dialog
      ref="removeDialog"
      type="alert"
      width="sm"
      :title="t('AGENTS.PANEL.REDESIGN_KNOWLEDGE.REMOVE_CONFIRM_TITLE')"
      :description="
        t('AGENTS.PANEL.REDESIGN_KNOWLEDGE.REMOVE_CONFIRM_DESC', {
          name: sourceToRemove?.reference || '',
        })
      "
      :show-confirm-button="false"
      :show-cancel-button="false"
      @close="sourceToRemove = null"
      @confirm="remove"
    >
      <template #footer>
        <div class="flex flex-wrap justify-end gap-3">
          <Button
            faded
            color="slate"
            size="md"
            class="min-h-11"
            :disabled="Boolean(removingId)"
            :label="t('AGENTS.PANEL.REDESIGN_SETTINGS.CANCEL')"
            data-action="remove-cancel"
            @click="removeDialog.close()"
          />
          <Button
            solid
            color="ruby"
            size="md"
            type="submit"
            class="min-h-11 !bg-n-ruby-11 !text-white dark:!text-n-navy hover:enabled:!bg-n-ruby-12 hover:enabled:!brightness-100 focus-visible:!brightness-100 focus-visible:!outline-n-ruby-11"
            :disabled="Boolean(removingId)"
            :is-loading="Boolean(removingId)"
            :label="t('AGENTS.PANEL.REDESIGN_KNOWLEDGE.REMOVE_CONFIRM_BUTTON')"
            data-action="confirm-dialog"
          />
        </div>
      </template>
    </Dialog>
  </section>
</template>
