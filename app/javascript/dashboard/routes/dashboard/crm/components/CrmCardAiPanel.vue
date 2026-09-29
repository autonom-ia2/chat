<script setup>
import { computed, ref, watch, onBeforeUnmount } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';
import CrmKanbanAPI from 'dashboard/api/crmKanban';

const props = defineProps({
  cardId: { type: [String, Number], default: null },
  initialSuggestion: { type: Object, default: null },
  canManageAi: { type: Boolean, default: false },
});

const emit = defineEmits(['updated']);

const { t } = useI18n();

const suggestion = ref(props.initialSuggestion);
const isLoading = ref(false);
const isEvaluating = ref(false);
let scopeSequence = 0;
let loadSequence = 0;
let evaluateSequence = 0;

const hasSuggestion = computed(() => Boolean(suggestion.value?.id));

const loadSuggestion = async () => {
  if (!props.cardId) return;
  const requestCardId = props.cardId;
  const requestScope = scopeSequence;
  loadSequence += 1;
  const requestId = loadSequence;
  isLoading.value = true;
  try {
    const response = await CrmKanbanAPI.getCurrentAiSuggestion(requestCardId);
    if (
      requestId !== loadSequence ||
      requestScope !== scopeSequence ||
      requestCardId !== props.cardId
    )
      return;
    suggestion.value = response.data.payload;
  } catch {
    if (
      requestId === loadSequence &&
      requestScope === scopeSequence &&
      requestCardId === props.cardId
    )
      suggestion.value = null;
  } finally {
    if (requestId === loadSequence) isLoading.value = false;
  }
};

const evaluateError = ref('');

const evaluateNow = async () => {
  if (!props.cardId) return;
  const requestCardId = props.cardId;
  const requestScope = scopeSequence;
  evaluateSequence += 1;
  const requestId = evaluateSequence;
  isEvaluating.value = true;
  evaluateError.value = '';
  try {
    const response = await CrmKanbanAPI.evaluateCardAi(requestCardId);
    if (
      requestId !== evaluateSequence ||
      requestScope !== scopeSequence ||
      requestCardId !== props.cardId
    )
      return;
    const payload = response.data.payload || {};
    if (payload.status === 'suggested' || payload.status === 'auto_moved') {
      suggestion.value = payload.suggestion || null;
    } else if (payload.status === 'below_threshold') {
      suggestion.value = null;
      evaluateError.value = t('CRM_KANBAN.AI_CARD.BELOW_THRESHOLD');
    } else if (payload.error) {
      suggestion.value = null;
      evaluateError.value = t('CRM_KANBAN.AI_CARD.SKIPPED', {
        reason: payload.error,
      });
    } else {
      suggestion.value = payload.suggestion || null;
    }
    emit('updated');
  } catch {
    if (
      requestId === evaluateSequence &&
      requestScope === scopeSequence &&
      requestCardId === props.cardId
    )
      useAlert(t('CRM_KANBAN.AI_CARD.EVALUATE_ERROR'));
  } finally {
    if (requestId === evaluateSequence) isEvaluating.value = false;
  }
};

const acceptSuggestion = async () => {
  if (!suggestion.value?.id) return;
  try {
    await CrmKanbanAPI.acceptAiSuggestion(suggestion.value.id);
    suggestion.value = null;
    emit('updated');
    useAlert(t('CRM_KANBAN.AI_CARD.ACCEPT_SUCCESS'));
  } catch {
    useAlert(t('CRM_KANBAN.AI_CARD.ACCEPT_ERROR'));
  }
};

const dismissSuggestion = async () => {
  if (!suggestion.value?.id) return;
  try {
    await CrmKanbanAPI.dismissAiSuggestion(suggestion.value.id);
    suggestion.value = null;
    emit('updated');
  } catch {
    useAlert(t('CRM_KANBAN.AI_CARD.DISMISS_ERROR'));
  }
};

watch(
  () => [props.cardId, props.initialSuggestion],
  () => {
    scopeSequence += 1;
    loadSequence += 1;
    evaluateSequence += 1;
    isLoading.value = false;
    isEvaluating.value = false;
    evaluateError.value = '';
    suggestion.value = props.initialSuggestion;
    if (props.cardId && !props.initialSuggestion) loadSuggestion();
  },
  { immediate: true }
);

onBeforeUnmount(() => {
  scopeSequence += 1;
  loadSequence += 1;
  evaluateSequence += 1;
});
</script>

<template>
  <section
    class="grid gap-3 rounded-lg border border-n-weak bg-n-alpha-black2 p-4"
  >
    <div class="flex items-center justify-between gap-3">
      <div>
        <h3 class="mb-1 text-sm font-medium text-n-slate-12">
          {{ t('CRM_KANBAN.AI_CARD.TITLE') }}
        </h3>
        <p class="mb-0 text-xs text-n-slate-11">
          {{ t('CRM_KANBAN.AI_CARD.HELP') }}
        </p>
      </div>
      <Button
        v-if="canManageAi"
        :label="t('CRM_KANBAN.AI_CARD.ANALYZE')"
        icon="i-lucide-sparkles"
        slate
        faded
        sm
        :is-loading="isEvaluating"
        @click="evaluateNow"
      />
    </div>

    <p v-if="isLoading" class="mb-0 text-xs text-n-slate-11">
      {{ t('CRM_KANBAN.AI_CARD.LOADING') }}
    </p>

    <div v-else-if="hasSuggestion" class="grid gap-2">
      <p class="mb-0 text-sm text-n-slate-12">
        {{
          t('CRM_KANBAN.AI_CARD.SUGGESTION', {
            stage: suggestion.to_stage_name,
          })
        }}
      </p>
      <p v-if="suggestion.reasoning" class="mb-0 text-xs text-n-slate-11">
        {{ suggestion.reasoning }}
      </p>
      <div v-if="canManageAi" class="flex flex-wrap gap-2">
        <Button
          :label="t('CRM_KANBAN.AI_CARD.ACCEPT')"
          sm
          @click="acceptSuggestion"
        />
        <Button
          :label="t('CRM_KANBAN.AI_CARD.DISMISS')"
          slate
          faded
          sm
          @click="dismissSuggestion"
        />
      </div>
    </div>

    <p v-else-if="evaluateError" class="mb-0 text-xs text-n-ruby-11">
      {{ evaluateError }}
    </p>

    <p v-else class="mb-0 text-xs text-n-slate-10">
      {{ t('CRM_KANBAN.AI_CARD.EMPTY') }}
    </p>
  </section>
</template>
