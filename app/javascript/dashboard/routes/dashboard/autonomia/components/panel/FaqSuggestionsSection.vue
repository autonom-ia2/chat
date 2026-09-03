<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute } from 'vue-router';
import { useStore } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import FaqSuggestionsAPI from 'dashboard/api/autonomia/faqSuggestions';
import { frontendURL, conversationUrl } from 'dashboard/helper/URLHelper';

import NextButton from 'dashboard/components-next/button/Button.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';

// #284 (2b) — "FAQ suggestions": toggle the generation per agent and review the
// pending pairs (approve / edit & approve / ignore). Approving writes a
// knowledge entry; the host refreshes the sources list on `approved`.
const props = defineProps({
  agent: { type: Object, required: true },
});

const emit = defineEmits(['approved']);

const { t } = useI18n();
const route = useRoute();
const store = useStore();

const suggestions = ref([]);
const meta = ref({});
const isFetching = ref(false);
const hasError = ref(false);
const busyId = ref(null);
const editingId = ref(null);
const editForm = ref({ question: '', answer: '' });
const isSavingToggle = ref(false);

const isEnabled = computed(() => props.agent.config?.faq_suggestions === true);
const pendingCount = computed(() => meta.value.pending_count ?? 0);

const fetchSuggestions = async () => {
  isFetching.value = true;
  hasError.value = false;
  try {
    const { data } = await FaqSuggestionsAPI.list(props.agent.id, {
      status: 'pending',
    });
    suggestions.value = data.payload || [];
    meta.value = data.meta || {};
  } catch (error) {
    hasError.value = true;
  } finally {
    isFetching.value = false;
  }
};

watch(() => props.agent.id, fetchSuggestions, { immediate: true });

const toggleGeneration = async value => {
  if (isSavingToggle.value) return;
  isSavingToggle.value = true;
  try {
    await store.dispatch('autonomiaAgents/update', {
      id: props.agent.id,
      config: { faq_suggestions: value },
    });
    useAlert(
      t(value ? 'AGENTS.FAQ.ENABLED_ALERT' : 'AGENTS.FAQ.DISABLED_ALERT')
    );
  } catch (error) {
    useAlert(t('AGENTS.FAQ.TOGGLE_ERROR'));
  } finally {
    isSavingToggle.value = false;
  }
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

const removeFromList = id => {
  suggestions.value = suggestions.value.filter(item => item.id !== id);
  meta.value = {
    ...meta.value,
    pending_count: Math.max((meta.value.pending_count ?? 1) - 1, 0),
  };
};

const startEdit = suggestion => {
  editingId.value = suggestion.id;
  editForm.value = { question: suggestion.question, answer: suggestion.answer };
};

const cancelEdit = () => {
  editingId.value = null;
};

const approve = async (suggestion, edits = null) => {
  busyId.value = suggestion.id;
  try {
    await FaqSuggestionsAPI.approve(props.agent.id, suggestion.id, edits);
    removeFromList(suggestion.id);
    editingId.value = null;
    useAlert(t('AGENTS.FAQ.APPROVE_SUCCESS'));
    emit('approved');
  } catch (error) {
    useAlert(error?.response?.data?.error || t('AGENTS.FAQ.APPROVE_ERROR'));
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
  try {
    await FaqSuggestionsAPI.ignore(props.agent.id, suggestion.id);
    removeFromList(suggestion.id);
    useAlert(t('AGENTS.FAQ.IGNORE_SUCCESS'));
  } catch (error) {
    useAlert(t('AGENTS.FAQ.IGNORE_ERROR'));
  } finally {
    busyId.value = null;
  }
};
</script>

<template>
  <section class="flex flex-col gap-4 pt-2 border-t border-n-weak">
    <div class="flex items-start justify-between gap-3">
      <div class="flex flex-col">
        <h3 class="text-sm font-medium text-n-slate-12">
          {{ t('AGENTS.FAQ.TITLE') }}
          <span
            v-if="pendingCount"
            class="ml-1 rounded-full bg-n-amber-3 px-1.5 py-0.5 text-xs text-n-amber-11"
            data-testid="faq-pending-count"
          >
            {{ pendingCount }}
          </span>
        </h3>
        <p class="m-0 text-xs text-n-slate-10">
          {{ t('AGENTS.FAQ.DESCRIPTION') }}
        </p>
      </div>
      <label class="flex items-center gap-2 text-xs text-n-slate-11">
        <span>{{ t('AGENTS.FAQ.TOGGLE') }}</span>
        <Switch
          :model-value="isEnabled"
          data-testid="faq-toggle"
          @update:model-value="toggleGeneration"
        />
      </label>
    </div>

    <div v-if="isFetching" class="flex items-center justify-center py-6">
      <Spinner :size="20" />
    </div>

    <p v-else-if="hasError" class="text-sm text-n-ruby-11">
      {{ t('AGENTS.FAQ.ERROR') }}
    </p>

    <p
      v-else-if="!suggestions.length"
      class="px-4 py-6 text-sm text-center border border-dashed rounded-xl border-n-weak text-n-slate-10"
    >
      {{ isEnabled ? t('AGENTS.FAQ.EMPTY') : t('AGENTS.FAQ.EMPTY_DISABLED') }}
    </p>

    <ul v-else class="flex flex-col gap-3">
      <li
        v-for="suggestion in suggestions"
        :key="suggestion.id"
        class="flex flex-col gap-3 px-4 py-4 border rounded-xl border-n-weak bg-n-solid-1"
        data-testid="faq-suggestion"
      >
        <template v-if="editingId === suggestion.id">
          <Input
            v-model="editForm.question"
            :label="t('AGENTS.FAQ.QUESTION')"
          />
          <TextArea
            v-model="editForm.answer"
            :label="t('AGENTS.FAQ.ANSWER')"
            auto-height
          />
          <div class="flex gap-2">
            <NextButton
              solid
              sm
              :label="t('AGENTS.FAQ.SAVE_AND_APPROVE')"
              :is-loading="busyId === suggestion.id"
              :disabled="busyId === suggestion.id"
              @click="approveEdited(suggestion)"
            />
            <NextButton
              ghost
              slate
              sm
              :label="t('AGENTS.FAQ.CANCEL')"
              @click="cancelEdit"
            />
          </div>
        </template>

        <template v-else>
          <div class="flex flex-col gap-1">
            <p class="m-0 text-sm font-medium text-n-slate-12">
              {{ suggestion.question }}
            </p>
            <p class="m-0 text-sm whitespace-pre-line text-n-slate-11">
              {{ suggestion.answer }}
            </p>
          </div>
          <div class="flex flex-wrap items-center gap-2">
            <NextButton
              solid
              sm
              :label="t('AGENTS.FAQ.APPROVE')"
              :is-loading="busyId === suggestion.id"
              :disabled="busyId === suggestion.id"
              @click="approve(suggestion)"
            />
            <NextButton
              outline
              slate
              sm
              :label="t('AGENTS.FAQ.EDIT_AND_APPROVE')"
              :disabled="busyId === suggestion.id"
              @click="startEdit(suggestion)"
            />
            <NextButton
              ghost
              slate
              sm
              :label="t('AGENTS.FAQ.IGNORE')"
              :disabled="busyId === suggestion.id"
              @click="ignore(suggestion)"
            />
            <a
              v-if="conversationPath(suggestion)"
              :href="conversationPath(suggestion)"
              target="_blank"
              rel="noopener noreferrer"
              class="ml-auto text-xs text-n-blue-11 hover:underline"
            >
              {{
                t('AGENTS.FAQ.OPEN_CONVERSATION', {
                  id: suggestion.conversation_display_id,
                })
              }}
            </a>
          </div>
        </template>
      </li>
    </ul>
  </section>
</template>
