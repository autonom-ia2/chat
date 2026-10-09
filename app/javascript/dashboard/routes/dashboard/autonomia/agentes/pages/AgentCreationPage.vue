<script setup>
import { computed, onMounted, ref, toRef, watch } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useStore } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { useCanManage } from 'dashboard/composables/useCanManage';

import AgentSteps from '../components/AgentSteps.vue';
import AgentBuildChoosePage from './AgentBuildChoosePage.vue';
import AgentBuildTellPage from './AgentBuildTellPage.vue';
import AgentTestPhone from '../components/AgentTestPhone.vue';
import AgentBuildGoLivePage from './AgentBuildGoLivePage.vue';
import AgentReadyPage from './AgentReadyPage.vue';
import { useAgentCreation } from '../composables/useAgentCreation.js';

const props = defineProps({
  agentId: { type: [String, Number], default: null },
  step: {
    type: String,
    default: 'choice',
    validator: value =>
      ['choice', 'tell', 'test', 'live', 'ready'].includes(value),
  },
});

const route = useRoute();
const router = useRouter();
const store = useStore();
const { t } = useI18n();
const canManage = useCanManage('autonomia_manage');
const creation = useAgentCreation({
  agentId: toRef(props, 'agentId'),
  step: toRef(props, 'step'),
});
const {
  currentStep,
  selectedType,
  actuation,
  withKnowledge,
  agent,
  agentId: resolvedAgentId,
  messages,
  knows,
  suggestedLinks,
  readyForTest,
  testValid,
  isTesting,
  isPublishing,
  isSaving,
  buildStatus,
  hasBuildError,
  error,
  eligibleChannels,
  connectedChannels,
  occupiedChannels,
  copilotAvailability,
  start,
  resume,
  loadAgent,
  send,
  retrySend,
  attach,
  loadSources,
  loadCopilotAvailability,
  loadChannels,
  loadReusableSources,
  copySource,
  addLink,
  test,
  savePresentation,
  publish,
} = creation;

const isStarting = ref(false);
const isCopying = ref(false);
const reusableSources = ref([]);
const testMessages = ref([]);
const testError = ref(null);
const selectedChannelNames = ref([]);
const entryError = ref(null);
const publishedAgent = ref(null);
const loadedAgentRecord = ref(null);
const reusableSourcesLoaded = ref(false);
const reusableSourcesLoading = ref(false);
const reusableSourcesError = ref(false);
const presentationRevision = ref(0);
const entryRetryKind = ref(null);
const entryErrorStatus = ref(null);
const entryErrorCode = ref(null);
let loadSequence = 0;

const STEP_INDEX = { choice: 1, tell: 2, test: 3, live: 4, ready: 4 };
const STEP_KEYS = ['choice', 'tell', 'test', 'live'];

const currentIndex = computed(() => STEP_INDEX[currentStep.value] || 1);
const reachable = computed(() => {
  if (currentStep.value === 'choice') return 1;
  if (currentStep.value === 'tell') return 2;
  if (currentStep.value === 'test') return readyForTest.value ? 3 : 2;
  return testValid.value ? 4 : 3;
});
const currentAgentId = computed(() => resolvedAgentId.value || props.agentId);
const canChooseInternalAllowed = computed(
  () => copilotAvailability.value?.can_choose_internal === true
);
const creationAgent = computed(
  () =>
    publishedAgent.value ||
    agent.value ||
    loadedAgentRecord.value || { id: currentAgentId.value }
);
const isManual = computed(() => creationAgent.value?.mode === 'manual');
const buildError = computed(
  () =>
    entryError.value ||
    (error.value ? t('AGENTS.CREATION.errors.generic') : null) ||
    (hasBuildError.value ? t('AGENTS.CREATION.errors.generic') : null)
);

const errorStatus = errorValue =>
  errorValue?.response?.status || errorValue?.status || null;
const errorCode = errorValue =>
  errorValue?.response?.data?.code ||
  errorValue?.response?.data?.error_code ||
  errorValue?.code ||
  null;

const isAccessOrMissingError = errorValue =>
  [401, 403, 404].includes(Number(errorStatus(errorValue)));

const accountId = computed(() => route.params.accountId);

const dismissError = () => {
  entryError.value = null;
  entryRetryKind.value = null;
  entryErrorStatus.value = null;
  entryErrorCode.value = null;
  error.value = null;
};

const goToList = () =>
  router.push({
    name: 'autonomia_agents_index',
    params: { accountId: accountId.value },
  });

const goToStep = step => {
  if (step === 'choice') {
    router.push({
      name: 'autonomia_agents_builder',
      params: { accountId: accountId.value },
    });
    return;
  }
  if (!currentAgentId.value) return;
  if (step === 'ready') {
    router.push({
      name: 'autonomia_agent_ready',
      params: { accountId: accountId.value, agentId: currentAgentId.value },
    });
    return;
  }
  router.push({
    name: 'autonomia_agent_build',
    params: {
      accountId: accountId.value,
      agentId: currentAgentId.value,
      step,
    },
  });
};

const onStepGo = number => {
  const step = STEP_KEYS[number - 1];
  if (!step || number > reachable.value) return;
  goToStep(step);
};

const onStart = async selection => {
  if (isStarting.value) return;
  isStarting.value = true;
  entryError.value = null;
  try {
    const result = await start(selection);
    const id = result?.agent_id || resolvedAgentId.value;
    if (!id) {
      entryError.value = t('AGENTS.CREATION.errors.start');
      return;
    }
    goToStep('tell');
  } catch {
    entryError.value = t('AGENTS.CREATION.errors.start');
  } finally {
    isStarting.value = false;
  }
};

const onChoiceSelect = selection => {
  selectedType.value = selection.type;
  actuation.value = selection.actuation;
  withKnowledge.value = selection.withKnowledge;
};

const onSend = async payload => {
  entryError.value = null;
  try {
    await send(payload);
  } catch {
    entryError.value = t('AGENTS.CREATION.errors.tell');
  }
};
const onRetryTell = async () => {
  entryError.value = null;
  try {
    await retrySend();
  } catch {
    entryError.value = t('AGENTS.CREATION.errors.tell');
  }
};
const onAttach = async payload => {
  entryError.value = null;
  try {
    await attach(payload.files || []);
  } catch {
    entryError.value = t('AGENTS.CREATION.errors.material');
  }
};

const onUseSuggestedLink = async link => {
  const url =
    link?.url || link?.reference || (typeof link === 'string' ? link : '');
  try {
    await addLink(url);
  } catch {
    useAlert(t('AGENTS.CREATION.errors.material'));
  }
};

const onTellContinue = () => {
  if (!readyForTest.value) return;
  goToStep('test');
};

const onTest = async payload => {
  testError.value = null;
  const lastMessage = testMessages.value[testMessages.value.length - 1];
  if (lastMessage?.role !== 'user' || lastMessage.content !== payload.message) {
    testMessages.value = [
      ...testMessages.value,
      { role: 'user', content: payload.message },
    ];
  }
  try {
    const result = await test(payload);
    const reply = result?.reply ?? result?.response;
    if (reply == null) {
      testError.value = t('AGENTS.CREATION.errors.test');
      return;
    }
    testMessages.value = [
      ...testMessages.value,
      {
        role: 'assistant',
        content: reply,
        confidence: result.confidence,
        handoff: result.handoff,
        usedKnowledge: result.used_knowledge || result.usedKnowledge || [],
        skippedTools: Array.isArray(result.skipped_tools)
          ? result.skipped_tools
          : [],
        writesExternal: result.writes_external === true,
      },
    ];
  } catch (testRequestError) {
    const status = testRequestError?.response?.status;
    testError.value =
      status === 429
        ? t('AGENTS.CREATION.test.rateLimited')
        : t('AGENTS.CREATION.errors.test');
  }
};

const onSavePresentation = async presentation => {
  try {
    const result = await savePresentation(presentation);
    presentationRevision.value += 1;
    useAlert(t('AGENTS.CREATION.test.saved'));
    return result || true;
  } catch {
    useAlert(t('AGENTS.CREATION.errors.presentation'));
    return false;
  }
};

const onTestContinue = async presentation => {
  if (!testValid.value) return;
  if (presentation?.dirty) {
    await onSavePresentation(presentation);
    return;
  }
  goToStep('live');
};

const onTestLeave = async presentation => {
  if (presentation?.dirty && !(await onSavePresentation(presentation))) return;
  goToList();
};

const onClearTest = () => {
  testMessages.value = [];
  testError.value = null;
};

const onTestBack = () => {
  if (isManual.value) {
    router.push({
      name: 'autonomia_agent_panel',
      params: {
        accountId: accountId.value,
        agentId: currentAgentId.value,
        tab: 'tune',
      },
    });
    return;
  }
  goToStep('tell');
};

const onPublish = async payload => {
  entryError.value = null;
  selectedChannelNames.value = eligibleChannels.value
    .filter(channel => payload.inboxIds.includes(channel.id))
    .map(channel => channel.name);
  try {
    const result = await publish(payload);
    publishedAgent.value = result?.agent || result;
    goToStep('ready');
  } catch {
    entryError.value = t('AGENTS.CREATION.errors.publish');
  }
};

const onLeaveOff = () => goToList();

const onCopySource = async sourceId => {
  if (isCopying.value) return;
  isCopying.value = true;
  try {
    await copySource(sourceId);
  } catch {
    useAlert(t('AGENTS.CREATION.errors.material'));
  } finally {
    isCopying.value = false;
  }
};

const loadEntry = async (agentId = props.agentId, step = props.step) => {
  if (!agentId || step === 'choice') return;
  loadSequence += 1;
  const sequence = loadSequence;
  const isCurrent = () => sequence === loadSequence;
  const setEntryError = (messageKey, cause, retryKind) => {
    if (!isCurrent()) return;
    entryError.value = t(messageKey);
    entryRetryKind.value = retryKind;
    entryErrorStatus.value = errorStatus(cause);
    entryErrorCode.value = errorCode(cause);
    useAlert(entryError.value);
  };

  entryError.value = null;
  entryRetryKind.value = null;
  entryErrorStatus.value = null;
  entryErrorCode.value = null;
  error.value = null;
  reusableSourcesLoaded.value = false;
  reusableSourcesLoading.value = false;
  reusableSourcesError.value = false;

  const needsChannels = step === 'live' || step === 'ready';
  // Keep the independent live-channel read concurrent with the agent read,
  // but turn its rejection into data so it cannot become an unhandled promise
  // while the agent request is still in flight.
  const channelsRequest = needsChannels
    ? loadChannels()
        .then(payload => ({ payload }))
        .catch(channelsError => ({ error: channelsError }))
    : Promise.resolve({ payload: null });

  let loadedAgent;
  try {
    loadedAgent = await loadAgent(agentId);
  } catch (agentError) {
    if (!isCurrent()) return;
    if (isAccessOrMissingError(agentError)) {
      entryError.value = t('AGENTS.CREATION.errors.generic');
      entryErrorStatus.value = errorStatus(agentError);
      entryErrorCode.value = errorCode(agentError);
      useAlert(entryError.value);
      await goToList();
      return;
    }
    setEntryError('AGENTS.CREATION.errors.generic', agentError, 'agent');
    return;
  }
  if (!isCurrent()) return;
  if (loadedAgent?.id && Number(loadedAgent.id) === Number(agentId)) {
    loadedAgentRecord.value = loadedAgent;
  }

  const getter = store.getters?.['autonomiaAgents/getRecord'];
  const record =
    loadedAgent ||
    (typeof getter === 'function' ? getter(Number(agentId)) : null);

  // Conte is the only step that needs the persisted Builder conversation. API
  // and Guia agents can have an instruction without ever having a Builder
  // thread, so Teste/Ligue must never turn a legitimate deep link into a
  // resume 404 or invent a start/create fallback.
  if (step === 'tell' && (!record || record.mode !== 'manual')) {
    try {
      await resume(agentId);
    } catch (resumeError) {
      if (!isCurrent()) return;
      setEntryError('AGENTS.CREATION.errors.resume', resumeError, 'resume');
      return;
    }
    if (!isCurrent()) return;
  }

  const channelsResult = await channelsRequest;
  if (needsChannels) {
    if (channelsResult.error) {
      if (!isCurrent()) return;
      setEntryError(
        'AGENTS.CREATION.errors.generic',
        channelsResult.error,
        'channels'
      );
      return;
    }
    if (!isCurrent()) return;
    const connected =
      channelsResult.payload?.payload || connectedChannels.value || [];
    selectedChannelNames.value = connected.map(channel => channel.inbox_name);
  }

  if (step === 'tell') {
    try {
      await loadSources();
    } catch (sourcesError) {
      if (!isCurrent()) return;
      setEntryError('AGENTS.CREATION.errors.generic', sourcesError, 'sources');
      return;
    }
    if (!isCurrent()) return;

    reusableSourcesLoading.value = true;
    try {
      reusableSources.value = await loadReusableSources();
    } catch {
      reusableSources.value = [];
      reusableSourcesError.value = true;
    } finally {
      reusableSourcesLoading.value = false;
      reusableSourcesLoaded.value = true;
    }
  }
};

const retryEntry = () => loadEntry(props.agentId, props.step);

watch([() => props.agentId, () => props.step], ([agentId, value], previous) => {
  if (agentId !== previous?.[0]) {
    publishedAgent.value = null;
    loadedAgentRecord.value = null;
    selectedChannelNames.value = [];
    reusableSources.value = [];
    reusableSourcesLoaded.value = false;
    reusableSourcesLoading.value = false;
    reusableSourcesError.value = false;
  }
  if (['choice', 'tell', 'test', 'live', 'ready'].includes(value)) {
    currentStep.value = value;
  }
  if (value === 'choice') loadCopilotAvailability().catch(() => null);
  else if (agentId) loadEntry(agentId, value);
});

onMounted(async () => {
  await loadEntry();
  if (props.step === 'choice') loadCopilotAvailability().catch(() => null);
});
</script>

<template>
  <div class="flex flex-col w-full min-h-full overflow-y-auto bg-n-background">
    <div class="w-full max-w-6xl px-4 pt-4 mx-auto sm:px-6 lg:pt-6">
      <AgentSteps
        :current="currentIndex"
        :reachable="reachable"
        @go="onStepGo"
      />
    </div>

    <div v-if="buildError" class="w-full max-w-6xl px-4 mx-auto sm:px-6">
      <div
        class="flex items-start gap-3 p-4 border rounded-xl border-n-ruby-7 bg-n-ruby-3 text-n-ruby-11"
        data-testid="creation-entry-error"
        :data-error-status="entryErrorStatus || undefined"
        :data-error-code="entryErrorCode || undefined"
        role="alert"
      >
        <i
          class="mt-0.5 i-lucide-circle-alert size-5 shrink-0"
          aria-hidden="true"
        />
        <span class="flex-1 text-sm">{{ buildError }}</span>
        <button
          v-if="entryRetryKind"
          type="button"
          class="min-h-11 px-2 text-xs font-medium underline"
          data-action="creation-entry-retry"
          @click="retryEntry"
        >
          {{ t('AGENTS.CREATION.actions.retry') }}
        </button>
        <button
          type="button"
          class="min-h-11 px-2 text-xs font-medium underline"
          @click="dismissError"
        >
          {{ t('AGENTS.CREATION.actions.dismiss') }}
        </button>
      </div>
    </div>

    <AgentBuildChoosePage
      v-if="currentStep === 'choice'"
      :selected-type="selectedType"
      :can-choose-internal="canChooseInternalAllowed"
      :is-starting="isStarting"
      @select="onChoiceSelect"
      @continue="onStart"
      @leave="goToList"
    />

    <AgentBuildTellPage
      v-else-if="currentStep === 'tell'"
      :agent-id="currentAgentId"
      :messages="messages"
      :knows="knows"
      :suggested-links="suggestedLinks"
      :reusable-sources="reusableSources"
      :reusable-sources-loaded="reusableSourcesLoaded"
      :reusable-sources-loading="reusableSourcesLoading"
      :reusable-sources-error="reusableSourcesError"
      :is-internal="creationAgent.actuation === 'internal'"
      :is-sending="isSaving && buildStatus === 'processing'"
      :is-attaching="isSaving"
      :can-continue="readyForTest"
      :error="buildError"
      :is-copying="isCopying"
      @send="onSend"
      @attach="onAttach"
      @copy-source="onCopySource"
      @use-link="onUseSuggestedLink"
      @continue="onTellContinue"
      @retry="onRetryTell"
      @leave="goToList"
    />

    <AgentTestPhone
      v-else-if="currentStep === 'test'"
      :agent-id="currentAgentId"
      :agent="creationAgent"
      :messages="testMessages"
      :test-valid="testValid"
      :is-testing="isTesting"
      :is-saving="isSaving"
      :presentation-revision="presentationRevision"
      :error="testError"
      :is-internal="creationAgent.actuation === 'internal'"
      @test="onTest"
      @save-presentation="onSavePresentation"
      @continue="onTestContinue"
      @back="onTestBack"
      @leave="onTestLeave"
      @clear="onClearTest"
    />

    <AgentBuildGoLivePage
      v-else-if="currentStep === 'live'"
      :agent="creationAgent"
      :channels="eligibleChannels"
      :occupied-channels="occupiedChannels"
      :test-valid="testValid"
      :is-publishing="isPublishing"
      :can-manage="canManage"
      @publish="onPublish"
      @back="goToStep('test')"
      @leave="goToList"
      @leave-off="onLeaveOff"
    />

    <AgentReadyPage
      v-else
      :agent="creationAgent"
      :channel-names="selectedChannelNames"
      @list="goToList"
    />
  </div>
</template>
