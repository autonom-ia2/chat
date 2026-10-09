<script setup>
import { computed, onBeforeUnmount, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';

import AutonomiaAgentsAPI from 'dashboard/api/autonomia/agents';
import {
  isAbortError,
  useAbortableRequest,
} from 'dashboard/composables/useAbortableRequest';
import AgentTestPhone from '../AgentTestPhone.vue';

const props = defineProps({
  agentId: { type: Number, default: null },
  agent: { type: Object, required: true },
  canManage: { type: Boolean, default: false },
});

const emit = defineEmits(['teach']);

const TEST_DELAY_MS = 180 * 1000;
const RATE_LIMIT_COOLDOWN_MS = 60 * 1000;

const { t } = useI18n();
const messages = ref([]);
const status = ref(
  props.agent?.has_instruction === false ? 'assembling' : 'idle'
);
const error = ref(null);
const rateLimited = ref(false);
const requestVersion = ref(0);
const { run, abort, isPending } = useAbortableRequest();
let rateLimitTimer = null;
let delayTimer = null;

const isInternal = computed(() => props.agent?.actuation === 'internal');
const isQuote = computed(() => props.agent?.agent_type === 'insurance_quote');
const isTesting = computed(() => isPending.value);

const errorCode = requestError =>
  requestError?.code ||
  requestError?.response?.data?.code ||
  requestError?.response?.data?.error;

const statusForAgent = () =>
  props.agent?.has_instruction === false ? 'assembling' : 'idle';

const clearRateLimitTimer = () => {
  if (rateLimitTimer) clearTimeout(rateLimitTimer);
  rateLimitTimer = null;
};

const clearDelayTimer = () => {
  if (delayTimer) clearTimeout(delayTimer);
  delayTimer = null;
};

const startDelayTimer = version => {
  clearDelayTimer();
  delayTimer = setTimeout(() => {
    delayTimer = null;
    if (
      version === requestVersion.value &&
      isTesting.value &&
      status.value === 'thinking'
    ) {
      status.value = 'delayed';
    }
  }, TEST_DELAY_MS);
};

const startRateLimit = () => {
  clearRateLimitTimer();
  rateLimited.value = true;
  rateLimitTimer = setTimeout(() => {
    rateLimited.value = false;
    rateLimitTimer = null;
    if (status.value === 'rate_limited') {
      error.value = null;
      status.value = statusForAgent();
    }
  }, RATE_LIMIT_COOLDOWN_MS);
};

const invalidate = () => {
  requestVersion.value += 1;
  abort();
};

const clearConversation = () => {
  invalidate();
  clearDelayTimer();
  messages.value = [];
  error.value = null;
  status.value = rateLimited.value ? 'rate_limited' : statusForAgent();
};

const appendResult = result => {
  clearDelayTimer();
  const reply = result.reply;
  const hasReply = typeof reply === 'string' && reply.trim();
  if (result?.error && !hasReply) {
    status.value = 'error';
    return;
  }
  if (!hasReply) {
    status.value = 'empty';
    return;
  }

  messages.value.push({
    role: 'assistant',
    content: reply,
    confidence: result.confidence,
    handoff: result.handoff ?? null,
    usedKnowledge: result.used_knowledge,
    skippedTools: result.skipped_tools,
    writesExternal: result.writes_external === true,
  });
  status.value = 'success';
};

const runTest = async payload => {
  const message = payload?.message?.trim();
  const retryingDelayed = status.value === 'delayed' && isTesting.value;
  if (!props.agentId || !message || rateLimited.value) return;
  if (isTesting.value && !retryingDelayed) return;
  if (retryingDelayed) {
    invalidate();
    clearDelayTimer();
  }

  const version = requestVersion.value + 1;
  requestVersion.value = version;
  error.value = null;
  status.value = 'thinking';
  const lastMessage = messages.value[messages.value.length - 1];
  if (lastMessage?.role !== 'user' || lastMessage.content !== message) {
    messages.value.push({ role: 'user', content: message });
  }
  startDelayTimer(version);

  try {
    const response = await run(
      signal =>
        AutonomiaAgentsAPI.test(
          props.agentId,
          {
            message,
            history: payload.history || [],
            images: payload.images || [],
          },
          { signal }
        ),
      { onAbort: null }
    );

    if (!response || version !== requestVersion.value) return;
    appendResult(response.data);
  } catch (requestError) {
    if (isAbortError(requestError) || version !== requestVersion.value) return;

    clearDelayTimer();
    const code = errorCode(requestError);
    if (requestError?.response?.status === 429 || code === 'rate_limited') {
      startRateLimit();
      status.value = 'rate_limited';
    } else if (code === 'ai_request_timeout') {
      status.value = 'error';
    } else {
      status.value = 'error';
    }
    error.value = requestError;
  }
};

const errorMessage = computed(() => {
  if (status.value === 'rate_limited') {
    return t('AGENTS.PANEL.REDESIGN_TEST.RATE_LIMIT');
  }
  if (status.value === 'delayed') {
    return t('AGENTS.PANEL.REDESIGN_TEST.DELAY');
  }
  if (status.value === 'empty') {
    return t('AGENTS.PANEL.REDESIGN_TEST.EMPTY_RESPONSE');
  }
  if (status.value === 'error') {
    return t('AGENTS.PANEL.REDESIGN_TEST.NOT_RESPONDING');
  }
  return null;
});

const teach = () => {
  if (props.canManage && !isQuote.value) emit('teach');
};

watch([() => props.agentId, () => props.agent], () => {
  invalidate();
  clearRateLimitTimer();
  clearDelayTimer();
  rateLimited.value = false;
  messages.value = [];
  error.value = null;
  status.value = statusForAgent();
});

onBeforeUnmount(() => {
  clearRateLimitTimer();
  clearDelayTimer();
  invalidate();
});
</script>

<template>
  <section
    class="flex flex-col w-full gap-4"
    data-testid="agent-panel-test"
    :aria-busy="isTesting"
  >
    <div
      v-if="status === 'assembling'"
      class="flex items-start gap-2 p-3 text-sm rounded-xl bg-n-amber-9/10 text-n-amber-12"
      data-state="assembling"
      role="status"
    >
      <i class="mt-0.5 i-lucide-hammer size-5 shrink-0" aria-hidden="true" />
      <span>{{ t('AGENTS.PANEL.REDESIGN_TEST.ASSEMBLING') }}</span>
    </div>

    <div
      v-if="status === 'rate_limited'"
      class="flex items-start gap-2 p-3 text-sm rounded-xl bg-n-amber-9/10 text-n-amber-12"
      data-state="rate-limited"
      role="status"
    >
      <i class="mt-0.5 i-lucide-clock-3 size-5 shrink-0" aria-hidden="true" />
      <span>{{ t('AGENTS.PANEL.REDESIGN_TEST.RATE_LIMIT') }}</span>
    </div>

    <AgentTestPhone
      mode="panel"
      :agent-id="agentId"
      :agent="agent"
      :messages="messages"
      :is-testing="isTesting"
      :rate-limited="rateLimited"
      :delayed="status === 'delayed'"
      :is-internal="isInternal"
      :can-manage="canManage"
      :error="status === 'rate_limited' ? null : errorMessage"
      @test="runTest"
      @clear="clearConversation"
      @teach="teach"
    />
  </section>
</template>
