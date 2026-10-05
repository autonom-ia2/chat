<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

// Status of the conversion sent back to Meta for the open card. One row from
// GET crm/meta_conversions (latest per card); null hides the block.
const props = defineProps({
  conversion: { type: Object, default: null },
  // The card came from a landing page click (#1011). Without browser signals
  // the dispatcher skips with 'missing_ctwa_clid'; on these cards that skip
  // has a reason the operator must see (CA-3.4).
  fromWebsite: { type: Boolean, default: false },
});
const { t } = useI18n();
const NS = 'CRM_KANBAN.META_SYNC_STATUS';
const PILLS = {
  accepted: { tone: 'bg-n-teal-3 text-n-teal-11', label: 'CARD_SENT' },
  pending: { tone: 'bg-n-amber-3 text-n-amber-11', label: 'LABEL_PENDING' },
  error: { tone: 'bg-n-ruby-3 text-n-ruby-11', label: 'LABEL_ERROR' },
  skipped: { tone: 'bg-n-alpha-2 text-n-slate-11', label: 'LABEL_SKIPPED' },
};
// Skip reasons the operator can act on. 'missing_ctwa_clid' on a card that did
// not come from an ad nor a landing page keeps the drawer quiet, as before.
const SKIP_REASONS = {
  missing_pixel: 'SKIP_MISSING_PIXEL',
  event_too_old: 'SKIP_EVENT_TOO_OLD',
  missing_credentials: 'SKIP_MISSING_CREDENTIALS',
  no_meta_event: 'SKIP_NO_META_EVENT',
  missing_signals: 'SKIP_MISSING_SIGNALS',
};
const EVENT_LABELS = {
  won: 'EVENT_WON',
  lost: 'EVENT_LOST',
  moved: 'EVENT_MOVED',
};

const skipReasonKey = reason => {
  if (reason === 'missing_ctwa_clid' && props.fromWebsite) {
    return SKIP_REASONS.missing_signals;
  }
  return SKIP_REASONS[reason];
};

const state = computed(() => {
  const { status, error_message: message } = props.conversion || {};
  const pill = PILLS[status];
  if (!pill) return null;
  if (status === 'skipped') {
    const reason = skipReasonKey(message);
    return reason ? { ...pill, detail: t(`${NS}.${reason}`) } : null;
  }
  if (status === 'error') {
    return { ...pill, detail: t(`${NS}.ERROR_HINT`), raw: message || '' };
  }
  return { ...pill, detail: '' };
});

const eventLabel = computed(() => {
  const key = EVENT_LABELS[props.conversion?.event_type];
  return key ? t(`${NS}.${key}`) : '';
});
</script>

<template>
  <div class="flex flex-wrap items-center gap-2 empty:hidden">
    <template v-if="state">
      <span class="text-xs font-medium text-n-slate-11">
        {{ t(`${NS}.CARD_TITLE`) }}
      </span>
      <span
        class="px-2 py-1 text-xs font-medium rounded-md"
        :class="state.tone"
      >
        {{ t(`${NS}.${state.label}`) }}
      </span>
      <span v-if="eventLabel" class="w-full text-xs text-n-slate-10">
        {{ t(`${NS}.CARD_EVENT`, { event: eventLabel }) }}
      </span>
      <span
        v-if="state.detail"
        class="w-full break-words text-xs text-n-slate-11"
      >
        {{ state.detail }}
      </span>
      <details v-if="state.raw" class="w-full text-xs text-n-slate-10">
        <summary class="cursor-pointer select-none py-1">
          {{ t(`${NS}.ERROR_RAW`) }}
        </summary>
        <span class="block break-words">{{ state.raw }}</span>
      </details>
    </template>
  </div>
</template>
