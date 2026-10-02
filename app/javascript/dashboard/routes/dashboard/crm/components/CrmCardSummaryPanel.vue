<script setup>
import { computed, ref, watch, onBeforeUnmount } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import CrmKanbanAPI from 'dashboard/api/crmKanban';
import { relativeTimeFromISO } from 'shared/helpers/timeHelper';

const props = defineProps({
  card: { type: Object, default: null },
  // True once the RESOLVED detail payload has loaded for this card. Auto-gen is
  // anchored to this (not mount) so we never fire against the shallow board card.
  detailLoaded: { type: Boolean, default: false },
  canManageAi: { type: Boolean, default: false },
  aiEnabled: { type: Boolean, default: false },
});

const { t, locale } = useI18n();

// Hydrate directly from the detail payload's typed ai_summary (Wave A). The
// backend strips it when the conversation is not visible to the user.
const summary = ref(props.card?.ai_summary || null);
const isLoading = ref(false);
const error = ref('');
let scopeSequence = 0;
let requestSequence = 0;

const cardId = computed(() => props.card?.id || null);
const hasConversation = computed(() =>
  Boolean(props.card?.conversation_id || props.card?.conversation?.id)
);
const hasSummary = computed(() => Boolean(summary.value?.text));
const lastUpdated = computed(() =>
  summary.value?.generated_at
    ? relativeTimeFromISO(summary.value.generated_at, locale.value)
    : ''
);

const generateSummary = async () => {
  if (!cardId.value || isLoading.value) return;
  const requestCardId = cardId.value;
  const requestScope = scopeSequence;
  requestSequence += 1;
  const requestId = requestSequence;
  isLoading.value = true;
  error.value = '';
  try {
    const response =
      await CrmKanbanAPI.summarizeCardConversation(requestCardId);
    if (
      requestId !== requestSequence ||
      requestScope !== scopeSequence ||
      requestCardId !== cardId.value
    )
      return;
    const payload = response.data.payload || {};
    if (payload.ai_summary?.text) {
      summary.value = payload.ai_summary;
    } else {
      error.value = t('CRM_KANBAN.AI_SUMMARY.ERROR');
    }
  } catch {
    if (
      requestId === requestSequence &&
      requestScope === scopeSequence &&
      requestCardId === cardId.value
    )
      error.value = t('CRM_KANBAN.AI_SUMMARY.ERROR');
  } finally {
    if (requestId === requestSequence) isLoading.value = false;
  }
};

// Anchor on the resolved detail load: only auto-generate when AI is enabled, a
// conversation is present, the detail payload has loaded and there is no fresh
// summary already in the payload.
watch(
  () => [cardId.value, props.detailLoaded, props.card?.ai_summary],
  () => {
    scopeSequence += 1;
    requestSequence += 1;
    isLoading.value = false;
    summary.value = props.card?.ai_summary || null;
    error.value = '';
    if (
      props.aiEnabled &&
      props.detailLoaded &&
      hasConversation.value &&
      !hasSummary.value &&
      !isLoading.value
    ) {
      generateSummary();
    }
  },
  { immediate: true }
);

onBeforeUnmount(() => {
  scopeSequence += 1;
  requestSequence += 1;
});
</script>

<!-- eslint-disable-next-line vue/no-root-v-if -->
<template>
  <section
    v-if="aiEnabled && hasConversation"
    class="grid gap-3 rounded-xl border border-n-weak bg-n-surface-1 p-4"
  >
    <div class="flex flex-wrap items-start justify-between gap-3">
      <div class="min-w-0">
        <h3 class="mb-1 text-sm font-medium text-n-slate-12">
          {{ t('CRM_KANBAN.AI_SUMMARY.TITLE') }}
        </h3>
        <p v-if="lastUpdated" class="mb-0 text-xs text-n-slate-10">
          {{ t('CRM_KANBAN.AI_SUMMARY.LAST_UPDATED', { time: lastUpdated }) }}
        </p>
      </div>
      <Button
        v-if="canManageAi"
        :label="t('CRM_KANBAN.AI_SUMMARY.REFRESH')"
        icon="i-lucide-refresh-cw"
        slate
        faded
        sm
        class="min-w-max shrink-0"
        :is-loading="isLoading"
        @click="generateSummary"
      />
    </div>

    <p v-if="isLoading" class="mb-0 text-xs text-n-slate-11">
      {{ t('CRM_KANBAN.AI_SUMMARY.LOADING') }}
    </p>

    <p
      v-else-if="hasSummary"
      class="mb-0 whitespace-pre-line text-sm leading-6 text-n-slate-12"
    >
      {{ summary.text }}
    </p>

    <p v-else-if="error" class="mb-0 text-xs text-n-ruby-11">
      {{ error }}
    </p>

    <p v-else class="mb-0 text-xs text-n-slate-10">
      {{ t('CRM_KANBAN.AI_SUMMARY.EMPTY') }}
    </p>
  </section>
</template>
