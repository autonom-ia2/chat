import { computed, ref, toValue, watch } from 'vue';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import AutonomiaAgentsAPI from 'dashboard/api/autonomia/agents';
import AutonomiaSourcesAPI from 'dashboard/api/autonomia/sources';

const STEP_KEYS = ['choice', 'tell', 'test', 'live', 'ready'];

const unwrap = response =>
  response?.data?.payload || response?.data || response;

// A test only unlocks Ligue when the backend has recorded a current, authorized
// result. A playground reply is useful feedback, but it is not proof that the
// result can be used for publishing. The list/show projection exposes either
// the state machine's E4 or the explicit test-result publication decision.
const canPublishFrom = value =>
  value?.state?.code === 'E4' || value?.test_result?.can_publish === true;

export const useAgentCreation = ({
  agentId: agentIdSource = null,
  step: stepSource = 'choice',
} = {}) => {
  const store = useStore();
  const initialAgentId = toValue(agentIdSource);
  const initialStep = toValue(stepSource);
  const currentStep = ref(
    STEP_KEYS.includes(initialStep) ? initialStep : 'choice'
  );
  const draftAgentId = ref(initialAgentId);
  const selectedType = ref(null);
  const actuation = ref('external');
  const withKnowledge = ref(true);
  const testValid = ref(false);
  const testResult = ref(null);
  const isTesting = ref(false);
  const isPublishing = ref(false);
  const error = ref(null);
  const copilotAvailability = ref(null);
  const lastSendPayload = ref(null);
  const invalidatedPresentationAgentId = ref(null);

  const thread = useMapGetter('autonomiaBuildThreads/getThread');
  const messages = useMapGetter('autonomiaBuildThreads/getMessages');
  const threadState = useMapGetter('autonomiaBuildThreads/getThreadState');
  const buildStatus = useMapGetter('autonomiaBuildThreads/getStatus');
  const buildPhase = useMapGetter('autonomiaBuildThreads/getPhase');
  const buildError = useMapGetter('autonomiaBuildThreads/getError');
  const buildFlags = useMapGetter('autonomiaBuildThreads/getUIFlags');
  const generatedAgent = useMapGetter('autonomiaBuildThreads/getAgent');
  const sources = useMapGetter('autonomiaSources/getSources');
  const sourceFlags = useMapGetter('autonomiaSources/getUIFlags');
  const eligibleChannels = useMapGetter('autonomiaChannels/getEligible');
  const channelFlags = useMapGetter('autonomiaChannels/getUIFlags');
  const occupiedChannels = ref([]);
  const connectedChannels = ref([]);

  const inputAgentId = computed(() => toValue(agentIdSource));

  const threadForAgent = computed(() => {
    const value = thread.value;
    if (!value || !draftAgentId.value) return null;
    if (
      value.agent_id &&
      Number(value.agent_id) !== Number(draftAgentId.value)
    ) {
      return null;
    }
    return value;
  });

  const scopedMessages = computed(() =>
    threadForAgent.value ? messages.value || [] : []
  );
  const scopedThreadState = computed(() =>
    threadForAgent.value ? threadState.value : null
  );
  const scopedBuildStatus = computed(() =>
    threadForAgent.value ? buildStatus.value : null
  );
  const scopedBuildPhase = computed(() =>
    threadForAgent.value ? buildPhase.value : null
  );
  const scopedBuildError = computed(() =>
    threadForAgent.value ? buildError.value : null
  );
  const scopedGeneratedAgent = computed(() => {
    const value = generatedAgent.value;
    if (!value || !draftAgentId.value || !value.id) return value;
    return Number(value.id) === Number(draftAgentId.value) ? value : null;
  });

  const storedAgent = computed(() => {
    const getter = store.getters?.['autonomiaAgents/getRecord'];
    if (typeof getter !== 'function' || !draftAgentId.value) return null;
    const value = getter(Number(draftAgentId.value));
    return value?.id ? value : null;
  });
  const agent = computed(
    () => storedAgent.value || scopedGeneratedAgent.value || null
  );
  const resolvedAgentId = computed(
    () =>
      draftAgentId.value ||
      threadForAgent.value?.agent_id ||
      scopedGeneratedAgent.value?.id ||
      storedAgent.value?.id ||
      null
  );
  const threadId = computed(() => threadForAgent.value?.id || null);
  const isSaving = computed(
    () =>
      Boolean(buildFlags.value?.creating || buildFlags.value?.sending) ||
      Boolean(sourceFlags.value?.creatingItem) ||
      isTesting.value ||
      isPublishing.value
  );
  const hasBuildError = computed(() =>
    Boolean(
      error.value ||
        scopedBuildError.value ||
        scopedBuildStatus.value === 'failed'
    )
  );
  const knows = computed(() => scopedThreadState.value?.knows || {});
  const suggestedLinks = computed(
    () => scopedThreadState.value?.suggested_links || []
  );
  const readyForTest = computed(() => {
    const state = scopedThreadState.value || {};
    return (
      scopedBuildStatus.value === 'ready' && state.needs_more_info === false
    );
  });

  watch(
    () => toValue(stepSource),
    value => {
      if (STEP_KEYS.includes(value)) currentStep.value = value;
    }
  );

  watch(inputAgentId, value => {
    if (value === draftAgentId.value) return;
    draftAgentId.value = value || null;
    testValid.value = false;
    testResult.value = null;
    invalidatedPresentationAgentId.value = null;
    error.value = null;
    occupiedChannels.value = [];
    connectedChannels.value = [];
  });

  watch(
    agent,
    value => {
      if (!value) return;
      if (!draftAgentId.value && value.id) draftAgentId.value = value.id;
      if (
        invalidatedPresentationAgentId.value &&
        Number(value.id) === Number(invalidatedPresentationAgentId.value)
      ) {
        testValid.value = false;
        return;
      }
      invalidatedPresentationAgentId.value = null;
      testValid.value = canPublishFrom(value);
    },
    { immediate: true }
  );

  const start = async ({
    type,
    actuation: nextActuation = 'external',
    withKnowledge: includeKnowledge = true,
  }) => {
    error.value = null;
    selectedType.value = type;
    actuation.value = nextActuation;
    withKnowledge.value = includeKnowledge;
    const payload = await store.dispatch('autonomiaBuildThreads/start', {
      type,
      actuation: nextActuation,
      with_knowledge: includeKnowledge,
    });
    const result = unwrap(payload);
    if (result?.agent_id) draftAgentId.value = result.agent_id;
    return result;
  };

  const resume = async (agentIdOverride = null) => {
    const targetAgentId = Number(agentIdOverride || resolvedAgentId.value);
    if (!targetAgentId) return null;
    error.value = null;
    try {
      const payload = await store.dispatch('autonomiaBuildThreads/resume', {
        agentId: targetAgentId,
      });
      const result = unwrap(payload);
      if (result?.agent_id) draftAgentId.value = result.agent_id;
      return result;
    } catch (resumeError) {
      error.value = resumeError;
      throw resumeError;
    }
  };

  const send = async ({ content, images = [], extra = {} } = {}) => {
    if (!threadId.value || !content?.trim()) return null;
    error.value = null;
    const payload = {
      threadId: threadId.value,
      content: content.trim(),
    };
    if (images.length || Object.keys(extra).length) {
      payload.extra = { ...extra, images };
    }
    lastSendPayload.value = { content, images, extra };
    try {
      return await store.dispatch('autonomiaBuildThreads/send', payload);
    } catch (sendError) {
      error.value = sendError;
      throw sendError;
    }
  };

  const retrySend = () =>
    lastSendPayload.value ? send(lastSendPayload.value) : Promise.resolve(null);

  const attach = files => {
    if (!resolvedAgentId.value || !files?.length) return Promise.resolve([]);
    return Promise.all(
      files.map(file =>
        store.dispatch('autonomiaSources/create', {
          agentId: Number(resolvedAgentId.value),
          descriptor: { file, kind: 'knowledge' },
        })
      )
    );
  };

  const loadSources = () =>
    resolvedAgentId.value
      ? store.dispatch('autonomiaSources/fetch', {
          agentId: Number(resolvedAgentId.value),
        })
      : Promise.resolve([]);

  const loadAgent = async (agentIdOverride = null) => {
    const targetAgentId = Number(agentIdOverride || resolvedAgentId.value);
    if (!targetAgentId) return null;
    const payload = await store.dispatch(
      'autonomiaAgents/show',
      targetAgentId,
      { root: true }
    );
    return unwrap(payload) || storedAgent.value;
  };

  const loadCopilotAvailability = async () => {
    const response = await AutonomiaAgentsAPI.get();
    copilotAvailability.value = response?.data?.copilot_availability || null;
    return copilotAvailability.value;
  };

  const loadChannels = async () => {
    if (!resolvedAgentId.value) {
      occupiedChannels.value = [];
      connectedChannels.value = [];
      return [];
    }
    occupiedChannels.value = [];
    connectedChannels.value = [];
    const payload = await store.dispatch('autonomiaChannels/fetch', {
      agentId: Number(resolvedAgentId.value),
    });
    connectedChannels.value =
      payload?.payload || payload?.connected_inboxes || [];
    occupiedChannels.value = payload?.occupied_inboxes || [];
    return payload;
  };

  const loadReusableSources = async () => {
    if (!resolvedAgentId.value) return [];
    const response = await AutonomiaSourcesAPI.reusable(
      Number(resolvedAgentId.value)
    );
    return unwrap(response) || [];
  };

  const copySource = async sourceId => {
    if (!resolvedAgentId.value || !sourceId) return null;
    const response = await AutonomiaSourcesAPI.copy(
      Number(resolvedAgentId.value),
      Number(sourceId)
    );
    await loadSources();
    return unwrap(response);
  };

  const addLink = async url => {
    if (!resolvedAgentId.value || !url?.trim()) return null;
    const response = await AutonomiaSourcesAPI.create(
      Number(resolvedAgentId.value),
      { url: url.trim(), kind: 'knowledge' }
    );
    await loadSources();
    return unwrap(response);
  };

  const test = async ({ message, history = [], images = [] } = {}) => {
    if (!resolvedAgentId.value || !message?.trim()) return null;
    error.value = null;
    isTesting.value = true;
    try {
      const response = await AutonomiaAgentsAPI.test(
        Number(resolvedAgentId.value),
        { message: message.trim(), history, images }
      );
      const result = unwrap(response) || {};
      testResult.value = result;
      // The playground response contains the answer only. Refresh the agent
      // projection so E4/test_result.can_publish remains the single gate used
      // by both this screen and the publish endpoint.
      const refreshedAgent = await store.dispatch(
        'autonomiaAgents/show',
        Number(resolvedAgentId.value),
        { root: true }
      );
      invalidatedPresentationAgentId.value = null;
      testValid.value = canPublishFrom(refreshedAgent || storedAgent.value);
      return result;
    } catch (testError) {
      error.value = testError;
      throw testError;
    } finally {
      isTesting.value = false;
    }
  };

  const savePresentation = async ({ name, greeting } = {}) => {
    if (!resolvedAgentId.value) return null;
    error.value = null;
    const response = await store.dispatch('autonomiaAgents/update', {
      id: Number(resolvedAgentId.value),
      ...(name !== undefined ? { name } : {}),
      ...(greeting !== undefined ? { greeting } : {}),
    });
    // A presentation edit starts a new test only after the server accepted the
    // PATCH. Keeping the old proof through a failed request avoids disabling a
    // valid test for a change that never reached the agent.
    invalidatedPresentationAgentId.value = Number(resolvedAgentId.value);
    testValid.value = false;
    testResult.value = null;
    return response;
  };

  const publish = async ({ inboxIds = [], responseWindow = 'always' } = {}) => {
    if (!resolvedAgentId.value) return null;
    isPublishing.value = true;
    error.value = null;
    try {
      const response = await AutonomiaAgentsAPI.publish(
        Number(resolvedAgentId.value),
        { inboxIds, responseWindow }
      );
      return unwrap(response);
    } catch (publishError) {
      error.value = publishError;
      throw publishError;
    } finally {
      isPublishing.value = false;
    }
  };

  return {
    currentStep,
    selectedType,
    actuation,
    withKnowledge,
    agent,
    agentId: resolvedAgentId,
    thread: threadForAgent,
    threadId,
    messages: scopedMessages,
    threadState: scopedThreadState,
    buildStatus: scopedBuildStatus,
    buildPhase: scopedBuildPhase,
    sources,
    eligibleChannels,
    connectedChannels,
    occupiedChannels,
    channelFlags,
    knows,
    suggestedLinks,
    readyForTest,
    testValid,
    testResult,
    isTesting,
    isPublishing,
    copilotAvailability,
    isSaving,
    hasBuildError,
    error,
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
  };
};

export default useAgentCreation;
