<script setup>
import { computed, useId } from 'vue';
import { useI18n } from 'vue-i18n';
import {
  confirmationMeta,
  formatBookingTime,
  noticeKindKey,
  noticeStatusClass,
  skipReasonKey,
} from '../../helpers/meetingNotices';

// O que o cliente respondeu pelo link e como ficaram os avisos no WhatsApp
// (#1192, J4-A5). Só mostra: nada aqui muda a reunião.
const props = defineProps({
  meeting: { type: Object, required: true },
});

const { t, locale } = useI18n();
const titleId = useId();
const BASE = 'CRM_KANBAN.CALENDAR.MEETING_DETAIL';

const confirmation = computed(() =>
  confirmationMeta(props.meeting.confirmation_status)
);

const statusLabel = notice => {
  const status = t(
    `${BASE}.NOTICES.STATUS.${String(notice.status).toUpperCase()}`
  );
  if (notice.status !== 'skipped') return status;
  const reason = t(
    `${BASE}.NOTICES.SKIP_REASONS.${skipReasonKey(notice.skip_reason)}`
  );
  return `${status}: ${reason}`;
};

const notices = computed(() =>
  (props.meeting.notices || [])
    .filter(notice => noticeKindKey(notice.kind))
    .map(notice => ({
      ...notice,
      key: `${notice.kind}-${notice.due_at}`,
      kindLabel: t(`${BASE}.NOTICES.KINDS.${noticeKindKey(notice.kind)}`),
      when: formatBookingTime(notice.due_at, locale.value),
      status: statusLabel(notice),
      statusClass: noticeStatusClass(notice.status),
    }))
);

const hasFailure = computed(() =>
  (props.meeting.notices || []).some(notice => notice.status === 'failed')
);
// Separador visual entre dois trechos já traduzidos (não é texto a traduzir).
const SEPARATOR = ' · ';
</script>

<template>
  <section
    data-test="meeting-client-reply"
    class="grid gap-2"
    :aria-labelledby="titleId"
  >
    <h4 :id="titleId" class="mb-0 text-xs font-medium text-n-slate-11">
      {{ t(`${BASE}.CLIENT.TITLE`) }}
    </h4>
    <div class="flex flex-wrap items-center gap-2">
      <span
        v-if="confirmation"
        data-test="meeting-confirmation"
        :data-status="meeting.confirmation_status"
        class="inline-flex items-center gap-1 rounded-md px-2 py-1 text-[11px] font-medium"
        :class="confirmation.className"
      >
        <span class="size-3.5" :class="confirmation.icon" aria-hidden="true" />
        {{ t(`${BASE}.CLIENT.${confirmation.key}`) }}
      </span>
      <span
        v-if="meeting.notices_stopped"
        data-test="meeting-notices-stopped"
        class="inline-flex items-center gap-1 rounded-md bg-n-alpha-2 px-2 py-1 text-[11px] font-medium text-n-slate-11"
      >
        <span class="i-lucide-bell-off size-3.5" aria-hidden="true" />
        {{ t(`${BASE}.CLIENT.STOPPED`) }}
      </span>
    </div>

    <div v-if="notices.length" class="grid gap-1.5">
      <p class="mb-0 text-xs font-medium text-n-slate-11">
        {{ t(`${BASE}.NOTICES.TITLE`) }}
      </p>
      <ul class="m-0 grid list-none gap-1.5 p-0" data-test="meeting-notices">
        <li
          v-for="notice in notices"
          :key="notice.key"
          :data-notice="notice.kind"
          class="flex flex-wrap items-center justify-between gap-2 rounded-lg border border-n-weak bg-n-alpha-black2 px-3 py-2"
        >
          <span class="min-w-0 text-sm text-n-slate-12">
            {{ notice.kindLabel }}
            <span v-if="notice.when" class="text-xs text-n-slate-10">
              {{ SEPARATOR }}{{ notice.when }}
            </span>
          </span>
          <span
            class="rounded-md px-2 py-1 text-[11px] font-medium"
            :class="notice.statusClass"
          >
            {{ notice.status }}
          </span>
        </li>
      </ul>
      <p
        v-if="hasFailure"
        data-test="meeting-notice-failed"
        class="mb-0 text-xs text-n-ruby-11"
      >
        {{ t(`${BASE}.NOTICES.FAILED_HINT`) }}
      </p>
    </div>
  </section>
</template>
