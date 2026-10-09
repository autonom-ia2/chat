<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute } from 'vue-router';

import AutonomiaAgentsAPI from 'dashboard/api/autonomia/agents';
import AutonomiaFaqSuggestionsAPI from 'dashboard/api/autonomia/faqSuggestions';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';
import LabeledSwitch from 'dashboard/components-next/switch/LabeledSwitch.vue';
import {
  isAbortError,
  useAbortableRequest,
} from 'dashboard/composables/useAbortableRequest';
import { conversationUrl, frontendURL } from 'dashboard/helper/URLHelper';

const props = defineProps({
  agentId: { type: Number, required: true },
  agent: { type: Object, required: true },
  canManage: { type: Boolean, default: false },
});

const emit = defineEmits(['approved', 'updated']);
const { t } = useI18n();
const route = useRoute();
const { run, abort } = useAbortableRequest();

const suggestions = ref([]);
const meta = ref({});
const page = ref(1);
const state = ref('idle');
const busyId = ref(null);
const editingId = ref(null);
const editForm = ref({ question: '', answer: '' });
const enabled = ref(props.agent.config?.faq_suggestions === true);
const isToggling = ref(false);
const isLoadingMore = ref(false);
const actionError = ref('');

const perPage = computed(() => Number(meta.value.per_page || 25));
const pendingCount = computed(() => Number(meta.value.pending_count || 0));
const totalCount = computed(() =>
  Number(meta.value.count || pendingCount.value)
);
const hasMore = computed(
  () => suggestions.value.length < totalCount.value && perPage.value > 0
);
const toggleLabel = computed(() =>
  enabled.value
    ? t('AGENTS.PANEL.REDESIGN_KNOWLEDGE.FAQ_ON')
    : t('AGENTS.PANEL.REDESIGN_KNOWLEDGE.FAQ_OFF')
);

const normalizePayload = response => {
  const data = response?.data || response || {};
  return {
    payload: Array.isArray(data.payload) ? data.payload : [],
    meta: data.meta || {},
  };
};

const loadPage = async (targetPage = 1) => {
  if (!props.canManage) {
    abort();
    state.value = 'forbidden';
    return;
  }

  if (targetPage === 1) state.value = 'loading';
  else isLoadingMore.value = true;
  actionError.value = '';

  try {
    const response = await run(signal =>
      AutonomiaFaqSuggestionsAPI.list(props.agentId, {
        status: 'pending',
        page: targetPage,
        signal,
      })
    );
    if (!response) return;
    const next = normalizePayload(response);
    suggestions.value =
      targetPage === 1 ? next.payload : [...suggestions.value, ...next.payload];
    meta.value = next.meta;
    page.value = targetPage;
    state.value = 'ready';
  } catch (requestError) {
    if (isAbortError(requestError)) return;
    state.value = 'error';
  } finally {
    isLoadingMore.value = false;
  }
};

watch(
  [() => props.agentId, () => props.canManage],
  () => {
    enabled.value = props.agent.config?.faq_suggestions === true;
    page.value = 1;
    suggestions.value = [];
    loadPage();
  },
  { immediate: true }
);

watch(
  () => props.agent.config?.faq_suggestions,
  value => {
    if (!isToggling.value) enabled.value = value === true;
  }
);

const retry = () => loadPage(1);
const loadMore = () => {
  if (!isLoadingMore.value && hasMore.value) loadPage(page.value + 1);
};

const toggleGeneration = async () => {
  if (isToggling.value || !props.canManage) return;
  const nextValue = !enabled.value;
  isToggling.value = true;
  actionError.value = '';
  try {
    await AutonomiaAgentsAPI.update(props.agentId, {
      agent: { config: { faq_suggestions: nextValue } },
    });
    enabled.value = nextValue;
    emit('updated', nextValue);
  } catch {
    actionError.value = 'toggle';
  } finally {
    isToggling.value = false;
  }
};

const removeFromList = id => {
  suggestions.value = suggestions.value.filter(item => item.id !== id);
  meta.value = {
    ...meta.value,
    count: Math.max(totalCount.value - 1, 0),
    pending_count: Math.max(pendingCount.value - 1, 0),
  };
};

const approve = async (suggestion, edits = null) => {
  busyId.value = suggestion.id;
  actionError.value = '';
  try {
    await AutonomiaFaqSuggestionsAPI.approve(
      props.agentId,
      suggestion.id,
      edits
    );
    removeFromList(suggestion.id);
    editingId.value = null;
    emit('approved', suggestion);
  } catch {
    actionError.value = 'approve';
  } finally {
    busyId.value = null;
  }
};

const approveEdited = suggestion => {
  const question = editForm.value.question.trim();
  const answer = editForm.value.answer.trim();
  if (!question || !answer) return;
  approve(suggestion, { question, answer });
};

const ignore = async suggestion => {
  busyId.value = suggestion.id;
  actionError.value = '';
  try {
    await AutonomiaFaqSuggestionsAPI.ignore(props.agentId, suggestion.id);
    removeFromList(suggestion.id);
  } catch {
    actionError.value = 'ignore';
  } finally {
    busyId.value = null;
  }
};

const startEdit = suggestion => {
  editingId.value = suggestion.id;
  editForm.value = { question: suggestion.question, answer: suggestion.answer };
};

const cancelEdit = () => {
  editingId.value = null;
};

const conversationPath = suggestion => {
  if (!suggestion.conversation_display_id) return '';
  return frontendURL(
    conversationUrl({
      accountId: route.params.accountId,
      id: suggestion.conversation_display_id,
    })
  );
};
const actionErrorMessage = computed(() => {
  if (actionError.value === 'toggle') {
    return t('AGENTS.PANEL.REDESIGN_KNOWLEDGE.FAQ_TOGGLE_ERROR');
  }
  if (actionError.value === 'approve') {
    return t('AGENTS.PANEL.REDESIGN_KNOWLEDGE.FAQ_APPROVE_ERROR');
  }
  if (actionError.value === 'ignore') {
    return t('AGENTS.PANEL.REDESIGN_KNOWLEDGE.FAQ_IGNORE_ERROR');
  }
  return '';
});
</script>

<template>
  <section
    class="flex flex-col min-w-0 gap-4 pt-5 border-t border-n-weak"
    data-testid="faq-review"
  >
    <div v-if="state === 'forbidden'" data-state="forbidden">
      <p class="m-0 text-sm text-n-slate-11">
        {{ t('AGENTS.PANEL.REDESIGN_KNOWLEDGE.FAQ_VIEW_ONLY') }}
      </p>
    </div>

    <template v-else>
      <div
        class="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between"
      >
        <div class="min-w-0">
          <h3 class="m-0 text-base font-medium text-n-slate-12">
            {{ t('AGENTS.PANEL.REDESIGN_KNOWLEDGE.FAQ_TITLE') }}
            <span
              v-if="pendingCount"
              class="ms-1 rounded-full bg-n-amber-3 px-1.5 py-0.5 text-xs text-n-amber-12"
              data-testid="faq-pending-count"
            >
              {{ pendingCount }}
            </span>
          </h3>
          <p class="mt-1 mb-0 text-xs leading-5 text-n-slate-11">
            {{ t('AGENTS.PANEL.REDESIGN_KNOWLEDGE.FAQ_DESCRIPTION') }}
          </p>
        </div>

        <LabeledSwitch
          :checked="enabled"
          :disabled="isToggling"
          :label="toggleLabel"
          data-testid="faq-toggle"
          @toggle="toggleGeneration"
        />
      </div>

      <p
        v-if="actionErrorMessage"
        class="m-0 text-sm text-n-ruby-11"
        role="alert"
      >
        {{ actionErrorMessage }}
      </p>

      <div
        v-if="state === 'loading'"
        class="flex items-center justify-center py-8"
        role="status"
      >
        <span
          class="i-lucide-loader-circle size-5 animate-spin text-n-slate-11"
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
          {{ t('AGENTS.PANEL.REDESIGN_KNOWLEDGE.FAQ_ERROR') }}
        </p>
        <Button
          outline
          ruby
          size="sm"
          class="min-h-11"
          :label="t('AGENTS.PANEL.REDESIGN_KNOWLEDGE.RETRY')"
          data-action="retry-faq"
          @click="retry"
        />
      </div>

      <div
        v-else-if="!suggestions.length"
        class="px-4 py-6 text-sm text-center border border-dashed rounded-xl border-n-weak text-n-slate-11"
        data-state="empty"
      >
        {{
          enabled
            ? t('AGENTS.PANEL.REDESIGN_KNOWLEDGE.FAQ_EMPTY')
            : t('AGENTS.PANEL.REDESIGN_KNOWLEDGE.FAQ_EMPTY_DISABLED')
        }}
      </div>

      <ul v-else class="list-none flex flex-col gap-3">
        <li
          v-for="suggestion in suggestions"
          :key="suggestion.id"
          class="flex flex-col min-w-0 gap-3 p-4 border rounded-xl border-n-weak bg-n-solid-1"
          data-testid="faq-suggestion"
        >
          <template v-if="editingId === suggestion.id">
            <Input
              v-model="editForm.question"
              :label="t('AGENTS.PANEL.REDESIGN_KNOWLEDGE.FAQ_QUESTION')"
            />
            <TextArea
              v-model="editForm.answer"
              :label="t('AGENTS.PANEL.REDESIGN_KNOWLEDGE.FAQ_ANSWER')"
              auto-height
            />
            <div class="flex flex-wrap gap-2">
              <Button
                solid
                size="sm"
                class="min-h-11 !bg-n-blue-11 !text-white dark:!text-n-navy hover:enabled:!bg-n-blue-12 hover:enabled:!brightness-100 focus-visible:!brightness-100 focus-visible:!outline-n-blue-11"
                :label="
                  t('AGENTS.PANEL.REDESIGN_KNOWLEDGE.FAQ_SAVE_AND_APPROVE')
                "
                :is-loading="busyId === suggestion.id"
                :disabled="busyId === suggestion.id"
                data-action="save-approve"
                @click="approveEdited(suggestion)"
              />
              <Button
                ghost
                slate
                size="sm"
                class="min-h-11"
                :label="t('AGENTS.PANEL.REDESIGN_KNOWLEDGE.FAQ_CANCEL')"
                data-action="cancel-edit"
                @click="cancelEdit"
              />
            </div>
          </template>

          <template v-else>
            <div class="flex flex-col min-w-0 gap-1">
              <p class="m-0 text-sm font-medium text-n-slate-12">
                {{ suggestion.question }}
              </p>
              <p
                class="m-0 text-sm leading-5 whitespace-pre-line text-n-slate-11"
              >
                {{ suggestion.answer }}
              </p>
            </div>
            <div class="flex flex-wrap items-center gap-2">
              <Button
                solid
                size="sm"
                class="min-h-11 !bg-n-blue-11 !text-white dark:!text-n-navy hover:enabled:!bg-n-blue-12 hover:enabled:!brightness-100 focus-visible:!brightness-100 focus-visible:!outline-n-blue-11"
                :label="t('AGENTS.PANEL.REDESIGN_KNOWLEDGE.FAQ_APPROVE')"
                :is-loading="busyId === suggestion.id"
                :disabled="busyId === suggestion.id"
                data-action="approve"
                @click="approve(suggestion)"
              />
              <Button
                outline
                slate
                size="sm"
                class="min-h-11"
                :label="
                  t('AGENTS.PANEL.REDESIGN_KNOWLEDGE.FAQ_EDIT_AND_APPROVE')
                "
                :disabled="busyId === suggestion.id"
                data-action="edit-approve"
                @click="startEdit(suggestion)"
              />
              <Button
                ghost
                slate
                size="sm"
                class="min-h-11"
                :label="t('AGENTS.PANEL.REDESIGN_KNOWLEDGE.FAQ_IGNORE')"
                :disabled="busyId === suggestion.id"
                data-action="ignore"
                @click="ignore(suggestion)"
              />
              <a
                v-if="conversationPath(suggestion)"
                :href="conversationPath(suggestion)"
                target="_blank"
                rel="noopener noreferrer"
                class="ms-auto min-h-11 inline-flex items-center text-xs text-n-blue-11 hover:underline"
              >
                {{
                  t('AGENTS.PANEL.REDESIGN_KNOWLEDGE.FAQ_FROM_CONVERSATION', {
                    id: suggestion.conversation_display_id,
                  })
                }}
              </a>
            </div>
          </template>
        </li>
      </ul>

      <Button
        v-if="hasMore && state === 'ready'"
        outline
        slate
        size="sm"
        class="self-start min-h-11"
        :label="t('AGENTS.PANEL.REDESIGN_KNOWLEDGE.FAQ_LOAD_MORE')"
        :is-loading="isLoadingMore"
        :disabled="isLoadingMore"
        data-action="load-more"
        @click="loadMore"
      />
    </template>
  </section>
</template>
