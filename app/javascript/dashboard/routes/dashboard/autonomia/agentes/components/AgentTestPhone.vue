<script setup>
import { computed, onBeforeUnmount, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';

import { useAlert } from 'dashboard/composables';
import NextButton from 'dashboard/components-next/button/Button.vue';
import ChatBubble from '../../components/builder/ChatBubble.vue';

const props = defineProps({
  agentId: { type: [String, Number], default: null },
  agent: { type: Object, default: null },
  messages: { type: Array, default: () => [] },
  testValid: { type: Boolean, default: false },
  isTesting: { type: Boolean, default: false },
  rateLimited: { type: Boolean, default: false },
  delayed: { type: Boolean, default: false },
  isSaving: { type: Boolean, default: false },
  isInternal: { type: Boolean, default: false },
  canManage: { type: Boolean, default: false },
  mode: {
    type: String,
    default: 'creation',
    validator: value => ['creation', 'panel'].includes(value),
  },
  presentationRevision: { type: Number, default: 0 },
  error: { type: [String, Object], default: null },
});

const emit = defineEmits([
  'test',
  'savePresentation',
  'continue',
  'back',
  'leave',
  'clear',
  'teach',
]);

const MAX_IMAGES = 4;
const MAX_IMAGE_BYTES = 5 * 1024 * 1024;
const IMAGE_EXTENSIONS = ['png', 'jpg', 'jpeg', 'gif', 'webp'];

const { t } = useI18n();
const useAlertMessage = useAlert;
const draft = ref('');
const name = ref('');
const greeting = ref('');
const savedName = ref('');
const savedGreeting = ref('');
const hydratedAgentId = ref(null);
const pendingImages = ref([]);
const fileInput = ref(null);
const lastSentMessage = ref('');
const presentationReset = ref(false);

const internal = computed(
  () => props.isInternal || props.agent?.actuation === 'internal'
);
const isPanel = computed(() => props.mode === 'panel');
const isQuote = computed(() => props.agent?.agent_type === 'insurance_quote');
const hasInstruction = computed(() => props.agent?.has_instruction !== false);
const writesExternal = computed(
  () =>
    props.agent?.writes_external === true ||
    props.agent?.config?.writes_external === true
);
const presentationDirty = computed(
  () =>
    name.value.trim() !== savedName.value.trim() ||
    (!internal.value && greeting.value.trim() !== savedGreeting.value.trim())
);
const canSend = computed(
  () => Boolean(draft.value.trim()) && !props.isTesting && !props.rateLimited
);
const errorText = computed(() =>
  typeof props.error === 'string'
    ? props.error
    : t(
        isPanel.value
          ? 'AGENTS.PANEL.REDESIGN_TEST.ERROR'
          : 'AGENTS.CREATION.errors.test'
      )
);

const HANDOFF_REASON_KEYS = {
  low_confidence: 'AGENTS.PERFORMANCE.REASONS.CODES.low_confidence',
  ai_unavailable: 'AGENTS.PERFORMANCE.REASONS.CODES.ai_unavailable',
  human_requested: 'AGENTS.PERFORMANCE.REASONS.CODES.human_requested',
  missing_knowledge: 'AGENTS.PERFORMANCE.REASONS.CODES.missing_knowledge',
  policy: 'AGENTS.PERFORMANCE.REASONS.CODES.policy',
  audience: 'AGENTS.PERFORMANCE.REASONS.CODES.audience',
  schedule: 'AGENTS.PERFORMANCE.REASONS.CODES.schedule',
  escolhas_incompletas: 'AGENTS.PERFORMANCE.REASONS.CODES.escolhas_incompletas',
  other: 'AGENTS.PERFORMANCE.REASONS.OTHER',
};

const handoffReason = handoff => {
  if (handoff?.reason_label) return handoff.reason_label;
  if (!handoff?.reason) {
    return t('AGENTS.PANEL.REDESIGN_TEST.HANDOFF_NO_REASON');
  }
  return t(
    HANDOFF_REASON_KEYS[handoff.reason] || 'AGENTS.PERFORMANCE.REASONS.OTHER'
  );
};

const confidenceWidth = confidence =>
  Math.max(0, Math.min(100, Math.round(Number(confidence) * 100)));
const confidenceLabel = confidence => `${confidenceWidth(confidence)}%`;

const confidenceColor = confidence => {
  const value = Number(confidence);
  if (value >= 0.7) return 'fill-n-teal-9';
  if (value >= 0.4) return 'fill-n-amber-9';
  return 'fill-n-ruby-9';
};

const questionKeys = {
  support: ['supportOne', 'supportTwo'],
  sdr: ['sdrOne', 'sdrTwo'],
  reception: ['receptionOne', 'receptionTwo'],
  onboarding: ['onboardingOne', 'onboardingTwo'],
  scheduler: ['schedulerOne', 'schedulerTwo'],
  reactivation: ['reactivationOne', 'reactivationTwo'],
  internal: ['internalOne', 'internalTwo'],
};
const typeKey = computed(() => {
  if (internal.value) return 'internal';
  const value = isPanel.value
    ? props.agent?.agent_type || 'support'
    : props.agent?.type || props.agent?.model || 'support';
  const normalizedValue = value === 'receptionist' ? 'reception' : value;
  return questionKeys[normalizedValue] ? normalizedValue : 'support';
});
const suggestedQuestions = computed(() =>
  (questionKeys[typeKey.value] || questionKeys.support).map(key =>
    t(`AGENTS.CREATION.test.questions.${key}`)
  )
);

const skippedToolMessage = tool => {
  const code = typeof tool === 'object' ? tool?.code : null;
  if (isPanel.value && isQuote.value && code === 'not_in_test') {
    return t('AGENTS.PANEL.REDESIGN_TEST.QUOTE_SKIPPED', {
      name: props.agent?.name || '',
    });
  }
  if (isPanel.value && code === 'viewer_not_allowed') {
    return t('AGENTS.PANEL.REDESIGN_TEST.VIEWER_TOOL_SKIPPED', {
      name: props.agent?.name || t('AGENTS.CREATION.test.agentFallback'),
      tool: tool?.name || tool?.slug || t('AGENTS.PANEL.REDESIGN_TEST.TOOL'),
    });
  }
  if (code === 'not_in_test') {
    return t('AGENTS.CREATION.test.toolNotInTest');
  }
  if (code === 'viewer_not_allowed') {
    return t('AGENTS.CREATION.test.toolViewerNotAllowed');
  }
  return t('AGENTS.CREATION.test.toolSkipped');
};

const hydratePresentation = value => {
  const nextAgentId = value?.id || props.agentId || null;
  const nextName = value?.name || value?.config?.name || '';
  const nextGreeting = value?.greeting || value?.config?.greeting || '';
  const isNewAgent = nextAgentId !== hydratedAgentId.value;
  if (nextAgentId !== hydratedAgentId.value || !presentationDirty.value) {
    name.value = nextName;
    greeting.value = nextGreeting;
    savedName.value = nextName;
    savedGreeting.value = nextGreeting;
    hydratedAgentId.value = nextAgentId;
    if (isNewAgent) presentationReset.value = false;
  }
};

watch(() => props.agent, hydratePresentation, { immediate: true });
watch(
  () => props.presentationRevision,
  (value, previous) => {
    if (value !== previous) {
      savedName.value = name.value;
      savedGreeting.value = greeting.value;
      lastSentMessage.value = '';
      presentationReset.value = true;
      emit('clear', { reason: 'presentation' });
    }
  }
);

const fileExtension = nameValue =>
  (nameValue.split('.').pop() || '').toLowerCase();
const isImage = file =>
  file?.type?.startsWith('image/') ||
  IMAGE_EXTENSIONS.includes(fileExtension(file?.name || ''));

const releaseImages = images =>
  images.forEach(image => {
    if (image.previewUrl) URL.revokeObjectURL(image.previewUrl);
  });

const addImages = files => {
  let invalid = false;
  let tooLarge = false;
  let tooMany = false;
  files.forEach(file => {
    if (!isImage(file)) {
      invalid = true;
      return;
    }
    if (file.size > MAX_IMAGE_BYTES) {
      tooLarge = true;
      return;
    }
    if (pendingImages.value.length >= MAX_IMAGES) {
      tooMany = true;
      return;
    }
    pendingImages.value.push({
      file,
      name: file.name,
      previewUrl: URL.createObjectURL(file),
    });
  });
  if (invalid) useAlertMessage(t('AGENTS.CREATION.test.imageInvalid'));
  if (tooLarge) useAlertMessage(t('AGENTS.CREATION.test.imageTooLarge'));
  if (tooMany) useAlertMessage(t('AGENTS.CREATION.test.imageTooMany'));
};

const onPickImages = event => {
  addImages(Array.from(event.target.files || []));
  if (fileInput.value) fileInput.value.value = '';
};

const openImagePicker = () => fileInput.value?.click();

const removeImage = index => {
  const [removed] = pendingImages.value.splice(index, 1);
  if (removed) releaseImages([removed]);
};

const fileToDataUrl = file =>
  new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => resolve(reader.result);
    reader.onerror = reject;
    reader.readAsDataURL(file);
  });

const send = async () => {
  if (!canSend.value) return;
  const content = draft.value.trim();
  const images = pendingImages.value.map(image => image.file);
  draft.value = '';
  releaseImages(pendingImages.value);
  pendingImages.value = [];
  lastSentMessage.value = content;
  emit('test', {
    message: content,
    images: await Promise.all(images.map(fileToDataUrl)),
    history: props.messages.map(message => ({
      role: message.role,
      content: message.content,
    })),
  });
};

const sendQuestion = question => {
  draft.value = question;
  send();
};

const retry = () => {
  if (
    !lastSentMessage.value ||
    props.rateLimited ||
    (props.isTesting && !props.delayed)
  )
    return;
  if (props.delayed) {
    emit('test', {
      message: lastSentMessage.value,
      images: [],
      history: props.messages.map(message => ({
        role: message.role,
        content: message.content,
      })),
    });
    return;
  }
  draft.value = lastSentMessage.value;
  send();
};

const clearConversation = () => {
  lastSentMessage.value = '';
  emit('clear');
};

const presentation = () => ({
  name: name.value.trim(),
  ...(internal.value ? {} : { greeting: greeting.value.trim() }),
  dirty: presentationDirty.value,
});

const savePresentation = () => emit('savePresentation', presentation());
const continueToLive = () => {
  if (props.testValid && !presentationDirty.value) {
    emit('continue', presentation());
  }
};

onBeforeUnmount(() => releaseImages(pendingImages.value));
</script>

<template>
  <main
    :data-testid="isPanel ? 'agent-panel-test-phone' : 'agent-creation-test'"
    :data-action="isPanel ? 'panel-test' : 'creation-test'"
    :data-agent-id="agentId || undefined"
    class="flex flex-col w-full max-w-6xl gap-6 px-4 py-6 mx-auto sm:px-6 lg:py-8"
  >
    <header v-if="!isPanel" class="flex flex-col gap-2">
      <div class="flex items-center justify-between gap-3">
        <div>
          <p
            class="text-xs font-semibold tracking-wider uppercase text-n-slate-11"
          >
            {{ t('AGENTS.CREATION.test.eyebrow') }}
          </p>
          <h1 class="mt-1 text-2xl font-semibold text-n-slate-12">
            {{ t('AGENTS.CREATION.test.title') }}
          </h1>
        </div>
        <NextButton
          ghost
          slate
          class="min-h-11"
          :label="t('AGENTS.CREATION.actions.leave')"
          data-action="creation-save-exit"
          @click="emit('leave', presentation())"
        />
      </div>
      <p class="max-w-2xl text-sm leading-6 text-n-slate-11">
        {{ t('AGENTS.CREATION.test.description') }}
      </p>
    </header>

    <header v-else class="flex flex-col gap-2">
      <div class="flex flex-col gap-1">
        <p
          class="text-xs font-semibold tracking-wider uppercase text-n-slate-11"
        >
          {{ t('AGENTS.PANEL.REDESIGN_TEST.EYEBROW') }}
        </p>
        <h1 class="text-2xl font-semibold text-n-slate-12">
          {{
            t('AGENTS.PANEL.REDESIGN_TEST.TITLE', {
              name: agent?.name || '',
            })
          }}
        </h1>
      </div>
      <p class="max-w-2xl text-sm leading-6 text-n-slate-11">
        {{ t('AGENTS.PANEL.REDESIGN_TEST.NOTHING_EXTERNAL') }}
      </p>
    </header>

    <div
      v-if="error"
      class="flex items-start gap-3 p-4 border rounded-xl border-n-ruby-7 bg-n-ruby-3 text-n-ruby-11"
      :role="delayed ? 'status' : 'alert'"
      :data-state="delayed ? 'delayed' : undefined"
    >
      <i
        class="mt-0.5 i-lucide-circle-alert size-5 shrink-0"
        aria-hidden="true"
      />
      <span class="flex-1 text-sm">{{ errorText }}</span>
      <NextButton
        v-if="lastSentMessage"
        ghost
        ruby
        class="min-h-11"
        :label="
          t(
            isPanel
              ? 'AGENTS.PANEL.REDESIGN_TEST.RETRY'
              : 'AGENTS.CREATION.actions.retry'
          )
        "
        data-action="test-retry"
        @click="retry"
      />
    </div>

    <section
      :class="
        isPanel
          ? 'grid gap-5 lg:grid-cols-[minmax(0,1.2fr)_minmax(18rem,0.8fr)]'
          : 'grid gap-5 lg:grid-cols-[minmax(0,0.8fr)_minmax(22rem,1.2fr)]'
      "
    >
      <section
        v-if="!isPanel"
        class="flex flex-col gap-4 p-5 border rounded-2xl border-n-weak bg-n-solid-1"
        aria-labelledby="agent-presentation-title"
      >
        <div>
          <h2
            id="agent-presentation-title"
            class="text-base font-semibold text-n-slate-12"
          >
            {{ t('AGENTS.CREATION.test.presentationTitle') }}
          </h2>
          <p class="mt-1 text-xs leading-5 text-n-slate-11">
            {{ t('AGENTS.CREATION.test.presentationDescription') }}
          </p>
        </div>

        <label class="flex flex-col gap-1.5 text-sm text-n-slate-11">
          <span>{{ t('AGENTS.CREATION.test.nameLabel') }}</span>
          <input
            v-model="name"
            type="text"
            class="min-h-11 w-full rounded-lg border border-n-weak bg-n-solid-1 px-3 py-2 text-sm text-n-slate-12 outline-none focus:border-n-brand"
            :aria-label="t('AGENTS.CREATION.test.nameLabel')"
            data-testid="presentation-name"
          />
        </label>
        <label
          v-if="!internal"
          class="flex flex-col gap-1.5 text-sm text-n-slate-11"
        >
          <span>{{ t('AGENTS.CREATION.test.greetingLabel') }}</span>
          <textarea
            v-model="greeting"
            rows="4"
            class="min-h-11 w-full resize-y rounded-lg border border-n-weak bg-n-solid-1 px-3 py-2 text-sm leading-6 text-n-slate-12 outline-none focus:border-n-brand"
            :aria-label="t('AGENTS.CREATION.test.greetingLabel')"
            data-testid="presentation-greeting"
          />
        </label>
        <NextButton
          outline
          slate
          block
          class="min-h-11"
          :disabled="!presentationDirty || isSaving"
          :label="t('AGENTS.CREATION.actions.savePresentation')"
          data-action="presentation-save"
          @click="savePresentation"
        />
        <p class="text-xs leading-5 text-n-slate-11">
          {{ t('AGENTS.CREATION.test.changeHint') }}
        </p>
        <p
          v-if="writesExternal"
          class="flex items-start gap-2 p-3 text-xs rounded-lg bg-n-amber-9/10"
          :class="isPanel ? 'text-n-amber-12' : 'text-n-amber-11'"
          role="status"
        >
          <i
            class="mt-0.5 i-lucide-shield-alert size-4 shrink-0"
            aria-hidden="true"
          />
          <span>{{ t('AGENTS.CREATION.test.writesExternal') }}</span>
        </p>
      </section>

      <section
        class="flex flex-col min-h-[30rem] gap-4 p-4 border rounded-2xl border-n-weak bg-n-alpha-1"
        :class="isPanel ? 'lg:order-1' : ''"
        :aria-labelledby="
          isPanel ? 'agent-panel-test-title' : 'agent-test-title'
        "
      >
        <div class="flex items-center gap-3 px-2">
          <span
            class="flex items-center justify-center rounded-xl size-10 bg-n-iris-3 text-n-iris-11"
          >
            <i class="i-lucide-smartphone size-5" aria-hidden="true" />
          </span>
          <div class="min-w-0">
            <h2
              :id="isPanel ? 'agent-panel-test-title' : 'agent-test-title'"
              class="text-sm font-semibold truncate text-n-slate-12"
            >
              {{ agent?.name || t('AGENTS.CREATION.test.agentFallback') }}
            </h2>
            <p v-if="isPanel" class="text-xs text-n-slate-11">
              {{ t('AGENTS.PANEL.REDESIGN_TEST.PRIVATE_BADGE') }}
            </p>
            <p v-else class="text-xs text-n-slate-11">
              {{ t('AGENTS.CREATION.test.privateHint') }}
            </p>
          </div>
        </div>

        <div
          v-if="!hasInstruction && !isPanel"
          class="flex items-start gap-2 px-3 py-2 text-xs rounded-lg bg-n-amber-9/10"
          :class="isPanel ? 'text-n-amber-12' : 'text-n-amber-11'"
          role="status"
        >
          <i
            class="mt-0.5 i-lucide-hammer size-4 shrink-0"
            aria-hidden="true"
          />
          {{
            t(
              isPanel
                ? 'AGENTS.PANEL.REDESIGN_TEST.ASSEMBLING'
                : 'AGENTS.CREATION.test.stillBuilding'
            )
          }}
        </div>
        <div
          v-if="internal"
          class="flex items-start gap-2 px-3 py-2 text-xs rounded-lg bg-n-iris-2 text-n-iris-11"
        >
          <i
            class="mt-0.5 i-lucide-messages-square size-4 shrink-0"
            aria-hidden="true"
          />
          <span>
            {{
              t(
                isPanel
                  ? 'AGENTS.PANEL.REDESIGN_TEST.INTERNAL_EXAMPLE'
                  : 'AGENTS.CREATION.test.internalExample'
              )
            }}
          </span>
        </div>
        <p v-else class="px-2 text-xs leading-5 text-n-slate-11">
          {{
            t(
              isPanel
                ? 'AGENTS.PANEL.REDESIGN_TEST.NO_SCHEDULE'
                : 'AGENTS.CREATION.test.noSchedule'
            )
          }}
        </p>

        <p
          v-if="!isPanel && presentationReset"
          class="flex items-start gap-2 px-3 py-2 text-xs leading-5 rounded-lg bg-n-iris-2 text-n-iris-11"
          data-testid="test-presentation-reset"
          role="status"
        >
          <i
            class="mt-0.5 i-lucide-refresh-cw size-4 shrink-0"
            aria-hidden="true"
          />
          <span>
            {{
              t('AGENTS.CREATION.test.presentationChanged', {
                name: name || t('AGENTS.CREATION.test.agentFallback'),
              })
            }}
          </span>
        </p>

        <div
          v-if="isPanel && writesExternal"
          class="flex items-start gap-2 px-3 py-2 text-xs rounded-lg bg-n-amber-9/10"
          :class="isPanel ? 'text-n-amber-12' : 'text-n-amber-11'"
          data-testid="panel-writes-external"
          role="status"
        >
          <i
            class="mt-0.5 i-lucide-shield-alert size-4 shrink-0"
            aria-hidden="true"
          />
          <span>{{ t('AGENTS.PANEL.REDESIGN_TEST.WRITES_EXTERNAL') }}</span>
        </div>

        <div
          class="flex flex-col flex-1 gap-3 p-3 overflow-y-auto rounded-xl bg-n-solid-1"
          role="log"
          aria-live="polite"
          :aria-label="t('AGENTS.CREATION.test.conversation')"
        >
          <p
            v-if="!messages.length"
            class="m-auto text-sm text-center text-n-slate-11"
          >
            {{ t('AGENTS.CREATION.test.empty') }}
          </p>
          <div
            v-if="!messages.length"
            class="flex flex-wrap justify-center gap-2"
          >
            <NextButton
              v-for="question in suggestedQuestions"
              :key="question"
              ghost
              slate
              class="min-h-11"
              :label="question"
              @click="sendQuestion(question)"
            />
          </div>
          <template
            v-for="(message, index) in messages"
            :key="`${message.role}-${index}`"
          >
            <ChatBubble :role="message.role" :content="message.content" />
            <div
              v-if="
                message.role === 'assistant' &&
                (message.confidence != null ||
                  message.handoff ||
                  message.usedKnowledge?.length ||
                  message.skippedTools?.length ||
                  message.writesExternal)
              "
              class="flex flex-col gap-2 pl-8"
            >
              <div
                v-if="message.confidence != null"
                class="flex items-center gap-2"
              >
                <span class="text-xs text-n-slate-11">
                  {{
                    t(
                      isPanel
                        ? 'AGENTS.PANEL.REDESIGN_TEST.CONFIDENCE'
                        : 'AGENTS.CREATION.test.confidence'
                    )
                  }}
                </span>
                <div
                  v-if="isPanel"
                  class="w-20 h-1.5 overflow-hidden rounded-full bg-n-alpha-2"
                  role="progressbar"
                  :aria-valuenow="confidenceWidth(message.confidence)"
                  aria-valuemin="0"
                  aria-valuemax="100"
                  :aria-label="t('AGENTS.PANEL.REDESIGN_TEST.CONFIDENCE')"
                  data-testid="test-confidence"
                >
                  <svg
                    class="block w-full h-full"
                    viewBox="0 0 100 4"
                    preserveAspectRatio="none"
                    aria-hidden="true"
                  >
                    <rect
                      x="0"
                      y="0"
                      width="100"
                      height="4"
                      class="fill-n-alpha-2"
                    />
                    <rect
                      x="0"
                      y="0"
                      :width="confidenceWidth(message.confidence)"
                      height="4"
                      :class="confidenceColor(message.confidence)"
                    />
                  </svg>
                </div>
                <div
                  v-else
                  class="w-20 h-1.5 overflow-hidden rounded-full bg-n-alpha-2"
                  role="progressbar"
                  :aria-valuenow="Math.round(message.confidence * 100)"
                  aria-valuemin="0"
                  aria-valuemax="100"
                  :aria-label="t('AGENTS.CREATION.test.confidence')"
                >
                  <div
                    class="h-full rounded-full bg-n-teal-9"
                    :style="{
                      width: `${Math.round(message.confidence * 100)}%`,
                    }"
                  />
                </div>
                <span class="text-xs tabular-nums text-n-slate-11">
                  {{ confidenceLabel(message.confidence) }}
                </span>
              </div>
              <div
                v-if="
                  message.handoff?.should && !internal && (!isPanel || !isQuote)
                "
                class="flex items-start gap-2 px-3 py-2 text-xs rounded-lg bg-n-amber-9/10"
                :class="isPanel ? 'text-n-amber-12' : 'text-n-amber-11'"
                data-testid="test-handoff"
                :data-state="isPanel ? 'handoff' : undefined"
              >
                <i
                  class="mt-0.5 i-lucide-user-round size-4 shrink-0"
                  aria-hidden="true"
                />
                <span v-if="isPanel">
                  {{ t('AGENTS.PANEL.REDESIGN_TEST.HANDOFF') }}
                  {{ handoffReason(message.handoff) }}
                </span>
                <span v-else>{{ t('AGENTS.CREATION.test.handoff') }}</span>
              </div>
              <div
                v-if="message.usedKnowledge?.length"
                class="flex flex-col gap-1 px-3 py-2 text-xs rounded-lg bg-n-teal-9/10"
                :class="isPanel ? 'text-n-teal-12' : 'text-n-teal-11'"
                data-testid="test-used-material"
              >
                <strong>
                  {{
                    t(
                      isPanel
                        ? 'AGENTS.PANEL.REDESIGN_TEST.USED_MATERIAL'
                        : 'AGENTS.CREATION.test.usedMaterials'
                    )
                  }}
                </strong>
                <span
                  v-for="item in message.usedKnowledge"
                  :key="item.source || item.content"
                >
                  {{ item.source || item.content }}
                </span>
              </div>
              <div
                v-if="message.skippedTools?.length"
                class="flex items-start gap-2 px-3 py-2 text-xs rounded-lg bg-n-slate-3 text-n-slate-11"
              >
                <i
                  class="mt-0.5 i-lucide-info size-4 shrink-0"
                  aria-hidden="true"
                />
                <span class="flex flex-col gap-1">
                  <span>
                    {{
                      t(
                        isPanel
                          ? 'AGENTS.PANEL.REDESIGN_TEST.SKIPPED_TOOLS'
                          : 'AGENTS.CREATION.test.skippedTools'
                      )
                    }}
                  </span>
                  <span
                    v-for="(tool, toolIndex) in message.skippedTools"
                    :key="tool.code || toolIndex"
                    :data-testid="
                      isPanel && isQuote && tool?.code === 'not_in_test'
                        ? 'quote-test-notice'
                        : undefined
                    "
                  >
                    {{ skippedToolMessage(tool) }}
                  </span>
                </span>
              </div>
              <div
                v-if="message.writesExternal"
                class="flex items-start gap-2 px-3 py-2 text-xs rounded-lg bg-n-amber-9/10"
                :class="isPanel ? 'text-n-amber-12' : 'text-n-amber-11'"
                data-testid="test-writes-external"
              >
                <i
                  class="mt-0.5 i-lucide-shield-alert size-4 shrink-0"
                  aria-hidden="true"
                />
                <span>
                  {{
                    t(
                      isPanel
                        ? 'AGENTS.PANEL.REDESIGN_TEST.WRITES_EXTERNAL'
                        : 'AGENTS.CREATION.test.writesExternal'
                    )
                  }}
                </span>
              </div>
            </div>
          </template>
          <div
            v-if="isTesting"
            class="flex items-center gap-2 text-xs text-n-slate-11"
            role="status"
          >
            <i
              class="i-lucide-loader-circle size-4 animate-spin"
              aria-hidden="true"
            />
            {{
              t(
                isPanel
                  ? 'AGENTS.PANEL.REDESIGN_TEST.THINKING'
                  : 'AGENTS.CREATION.test.thinking'
              )
            }}
          </div>
        </div>

        <NextButton
          v-if="messages.length"
          ghost
          slate
          class="self-start min-h-11"
          :label="
            t(
              isPanel
                ? 'AGENTS.PANEL.REDESIGN_TEST.CLEAR'
                : 'AGENTS.CREATION.test.clearConversation'
            )
          "
          data-action="test-clear"
          @click="clearConversation"
        />

        <div
          class="flex flex-col gap-2 p-1.5 border rounded-xl border-n-weak bg-n-solid-1"
        >
          <div v-if="pendingImages.length" class="flex flex-wrap gap-2 px-1">
            <div
              v-for="(image, index) in pendingImages"
              :key="image.name + index"
              class="flex items-center gap-2 py-1 pl-1 pr-2 border rounded-lg border-n-weak bg-n-alpha-1"
            >
              <img
                :src="image.previewUrl"
                :alt="image.name"
                class="object-cover rounded size-8"
              />
              <span class="max-w-32 text-xs truncate text-n-slate-11">
                {{ image.name }}
              </span>
              <button
                type="button"
                class="flex size-11 items-center justify-center rounded-lg text-n-slate-11 hover:bg-n-alpha-2"
                :aria-label="
                  t(
                    isPanel
                      ? 'AGENTS.PANEL.REDESIGN_TEST.REMOVE_IMAGE'
                      : 'AGENTS.CREATION.test.removeImage'
                  )
                "
                @click="removeImage(index)"
              >
                <i class="i-lucide-x size-4" aria-hidden="true" />
              </button>
            </div>
          </div>
          <div data-testid="test-composer" class="flex items-center gap-2">
            <button
              type="button"
              class="flex size-11 shrink-0 items-center justify-center rounded-lg text-n-slate-11 hover:bg-n-alpha-2"
              :aria-label="
                t(
                  isPanel
                    ? 'AGENTS.PANEL.REDESIGN_TEST.ADD_IMAGE'
                    : 'AGENTS.CREATION.test.addImage'
                )
              "
              :disabled="isTesting || rateLimited"
              @click="openImagePicker"
            >
              <i class="i-lucide-image-plus size-5" aria-hidden="true" />
            </button>
            <input
              ref="fileInput"
              type="file"
              class="hidden"
              accept="image/png,image/jpeg,image/gif,image/webp"
              multiple
              @change="onPickImages"
            />
            <textarea
              v-model="draft"
              rows="1"
              :disabled="isTesting || rateLimited"
              :placeholder="
                t(
                  isPanel
                    ? 'AGENTS.PANEL.REDESIGN_TEST.INPUT_PLACEHOLDER'
                    : 'AGENTS.CREATION.test.inputPlaceholder'
                )
              "
              :aria-label="
                t(
                  isPanel
                    ? 'AGENTS.PANEL.REDESIGN_TEST.INPUT_PLACEHOLDER'
                    : 'AGENTS.CREATION.test.inputPlaceholder'
                )
              "
              class="mb-0 h-16 min-h-11 max-h-28 flex-1 resize-none border-0 bg-transparent px-2 py-2 text-sm leading-6 text-n-slate-12 outline-none sm:h-11"
              data-testid="test-message"
              @keydown.enter.exact.prevent="send"
            />
            <button
              type="button"
              class="flex size-11 shrink-0 items-center justify-center rounded-lg bg-n-brand text-white disabled:opacity-40"
              :disabled="!canSend"
              :aria-label="
                t(
                  isPanel
                    ? 'AGENTS.PANEL.REDESIGN_TEST.SEND'
                    : 'AGENTS.CREATION.actions.test'
                )
              "
              data-action="test-send"
              @click="send"
            >
              <i class="i-lucide-arrow-up size-5" aria-hidden="true" />
            </button>
          </div>
          <p class="px-1 text-xs text-n-slate-11">
            {{
              t(
                isPanel
                  ? 'AGENTS.PANEL.REDESIGN_TEST.IMAGE_HINT'
                  : 'AGENTS.CREATION.test.imageHint'
              )
            }}
          </p>
        </div>
      </section>

      <aside
        v-if="isPanel"
        class="flex flex-col gap-4 p-5 border rounded-2xl border-n-weak bg-n-solid-1 lg:order-2"
        data-testid="agent-test-legend"
        aria-labelledby="agent-test-legend-title"
      >
        <h2
          id="agent-test-legend-title"
          class="text-base font-semibold text-n-slate-12"
        >
          {{ t('AGENTS.PANEL.REDESIGN_TEST.LEGEND_TITLE') }}
        </h2>
        <div class="flex flex-col gap-4">
          <div class="flex items-start gap-3">
            <span
              class="flex items-center justify-center rounded-lg size-8 shrink-0 bg-n-teal-3 text-n-teal-11"
              aria-hidden="true"
            >
              <i class="i-lucide-gauge size-4" />
            </span>
            <dl>
              <dt class="text-sm font-semibold text-n-slate-12">
                {{ t('AGENTS.PANEL.REDESIGN_TEST.LEGEND_CONFIDENCE') }}
              </dt>
              <dd class="mt-1 text-xs leading-5 text-n-slate-11">
                {{
                  t(
                    isInternal
                      ? 'AGENTS.PANEL.REDESIGN_TEST.LEGEND_CONFIDENCE_DESC_INTERNAL'
                      : isQuote
                        ? 'AGENTS.PANEL.REDESIGN_TEST.LEGEND_CONFIDENCE_DESC_QUOTE'
                        : 'AGENTS.PANEL.REDESIGN_TEST.LEGEND_CONFIDENCE_DESC',
                    { name: agent?.name || '' }
                  )
                }}
              </dd>
            </dl>
          </div>
          <div class="flex items-start gap-3">
            <span
              class="flex items-center justify-center rounded-lg size-8 shrink-0 bg-n-teal-3 text-n-teal-11"
              aria-hidden="true"
            >
              <i class="i-lucide-book-open size-4" />
            </span>
            <dl>
              <dt class="text-sm font-semibold text-n-slate-12">
                {{ t('AGENTS.PANEL.REDESIGN_TEST.LEGEND_MATERIAL') }}
              </dt>
              <dd class="mt-1 text-xs leading-5 text-n-slate-11">
                {{ t('AGENTS.PANEL.REDESIGN_TEST.LEGEND_MATERIAL_DESC') }}
              </dd>
            </dl>
          </div>
          <div
            v-if="!internal && !isQuote"
            class="flex items-start gap-3"
            data-testid="legend-handoff"
          >
            <span
              class="flex items-center justify-center rounded-lg size-8 shrink-0 bg-n-amber-3 text-n-amber-11"
              aria-hidden="true"
            >
              <i class="i-lucide-user-round size-4" />
            </span>
            <dl>
              <dt class="text-sm font-semibold text-n-slate-12">
                {{ t('AGENTS.PANEL.REDESIGN_TEST.LEGEND_HANDOFF') }}
              </dt>
              <dd class="mt-1 text-xs leading-5 text-n-slate-11">
                {{ t('AGENTS.PANEL.REDESIGN_TEST.LEGEND_HANDOFF_DESC') }}
              </dd>
            </dl>
          </div>
        </div>
        <NextButton
          v-if="canManage && !isQuote"
          outline
          slate
          block
          class="min-h-11"
          :label="t('AGENTS.PANEL.REDESIGN_TEST.TEACH')"
          data-action="test-teach"
          @click="emit('teach')"
        />
      </aside>
    </section>

    <div
      v-if="!isPanel"
      class="flex flex-col-reverse items-stretch justify-between gap-3 pt-4 border-t sm:flex-row sm:items-center border-n-weak"
    >
      <NextButton
        ghost
        slate
        class="min-h-11"
        :label="t('AGENTS.CREATION.actions.backToTell')"
        @click="emit('back')"
      />
      <NextButton
        solid
        slate
        class="min-h-11"
        :disabled="!testValid || presentationDirty || isSaving"
        :label="t('AGENTS.CREATION.actions.continueToLive')"
        data-action="creation-continue"
        data-testid="creation-test-next"
        @click="continueToLive"
      />
    </div>
  </main>
</template>
