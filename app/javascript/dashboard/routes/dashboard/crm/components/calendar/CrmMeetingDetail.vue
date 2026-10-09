<script setup>
import { computed, ref, watch, onBeforeUnmount } from 'vue';
import { useI18n } from 'vue-i18n';
import {
  differenceInMinutes,
  format,
  formatDistanceToNowStrict,
} from 'date-fns';
import { ptBR, enUS } from 'date-fns/locale';

import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import { useAlert } from 'dashboard/composables';
import crmMeetingsAPI from 'dashboard/api/crmMeetings';
import { resolveMeetingLocation } from '../../helpers/meetingLocation';

const props = defineProps({
  show: { type: Boolean, default: false },
  event: { type: Object, default: null },
  accountId: { type: [String, Number], default: '' },
  timezone: { type: String, default: '' },
});

const emit = defineEmits([
  'close',
  'openCard',
  'reschedule',
  'canceled',
  'updated',
]);

const { t, locale } = useI18n();

const detail = ref(null);
const isLoading = ref(false);
const loadError = ref(false);
const isSyncing = ref(false);
const isCanceling = ref(false);
const isRecordingOutcome = ref(false);
const cancelDialogRef = ref(null);
const isSummarizing = ref(false);
let summarizeRequestId = 0;
// AI (S5): gated on the install flag; backend enforces + degrades gracefully.
const aiEnabled = computed(
  () => window.globalConfig?.CRM_AI_ENABLED === 'true'
);

const dateFnsLocale = computed(() => (locale.value === 'pt_BR' ? ptBR : enUS));

const meetingId = computed(() => {
  const raw = props.event?.meeting_id || props.event?.id || '';
  return String(raw).replace(/^meeting_/, '');
});

const accountId = computed(() => {
  if (props.accountId) return props.accountId;
  if (window.location.pathname.includes('/app/accounts')) {
    return window.location.pathname.split('/')[3];
  }
  return '';
});

const meeting = computed(() => detail.value || props.event || {});

// Reunião interna (página de agendamento) não tem Meet nem Teams: mostra o
// local pelo rótulo próprio. Google e Microsoft seguem como antes.
const location = computed(() => resolveMeetingLocation(meeting.value));

const providerMeta = computed(() => {
  if (location.value.isInternal) {
    return {
      providerIcon: location.value.icon,
      joinIcon: 'i-lucide-link',
      joinClass: 'bg-n-brand text-white hover:bg-n-brand/90',
    };
  }
  const onlineType = meeting.value.online_meeting_type;
  const provider = meeting.value.provider;
  const isTeams = provider === 'microsoft' || onlineType === 'teams';

  return isTeams
    ? {
        providerIcon: 'i-logos-microsoft-icon',
        joinIcon: 'i-logos-microsoft-teams',
        joinClass: 'bg-[#6264a7] text-white hover:bg-[#5558a3]',
      }
    : {
        providerIcon: 'i-logos-google-icon',
        joinIcon: 'i-logos-google-meet',
        joinClass: 'bg-[#00897b] text-white hover:bg-[#00796b]',
      };
});

const toDate = value => {
  if (!value) return null;
  const date = value instanceof Date ? value : new Date(value);
  return Number.isNaN(date.getTime()) ? null : date;
};

const startsAt = computed(() => toDate(meeting.value.starts_at));
const endsAt = computed(() => toDate(meeting.value.ends_at));
const durationKeyByMinutes = {
  15: 'DURATION_15MIN',
  30: 'DURATION_30MIN',
  45: 'DURATION_45MIN',
  60: 'DURATION_1H',
  90: 'DURATION_1H30',
  120: 'DURATION_2H',
};

const startsAtLabel = computed(() => {
  if (!startsAt.value) return '';
  return format(startsAt.value, "dd/MM/yyyy 'as' HH:mm", {
    locale: dateFnsLocale.value,
  });
});

const relativeStartLabel = computed(() => {
  if (!startsAt.value) return '';
  return formatDistanceToNowStrict(startsAt.value, {
    addSuffix: true,
    locale: dateFnsLocale.value,
  });
});

const durationLabel = computed(() => {
  if (!startsAt.value || !endsAt.value) return '';
  const minutes = Math.max(
    differenceInMinutes(endsAt.value, startsAt.value),
    0
  );
  if (!minutes) return '';
  const durationKey = durationKeyByMinutes[minutes];
  if (durationKey) {
    return t(`CRM_KANBAN.CALENDAR.MEETING_SCHEDULER.${durationKey}`);
  }
  if (minutes < 60) {
    return t('CRM_KANBAN.CALENDAR.MEETING_SCHEDULER.DURATION_MINUTES', {
      count: minutes,
    });
  }

  const hours = Math.floor(minutes / 60);
  const rest = minutes % 60;
  return rest
    ? t('CRM_KANBAN.CALENDAR.MEETING_SCHEDULER.DURATION_HOURS_MINUTES', {
        hours,
        minutes: rest,
      })
    : t('CRM_KANBAN.CALENDAR.MEETING_SCHEDULER.DURATION_HOURS', {
        count: hours,
      });
});

const userTimezone = computed(
  () =>
    props.timezone ||
    Intl.DateTimeFormat().resolvedOptions().timeZone ||
    meeting.value.timezone ||
    'UTC'
);

const guests = computed(() => meeting.value.guests || []);

const statusLabel = computed(() => {
  const key = String(meeting.value.status || 'scheduled').toUpperCase();
  return t(`CRM_KANBAN.CALENDAR.MEETING_DETAIL.STATES.${key}`);
});

const rsvpMeta = status => {
  const normalized = String(status || 'rsvp_pending');
  const map = {
    rsvp_accepted: {
      label: t('CRM_KANBAN.CALENDAR.MEETING_DETAIL.RSVP.ACCEPTED'),
      className: 'bg-n-teal-9/10 text-n-teal-11',
    },
    rsvp_declined: {
      label: t('CRM_KANBAN.CALENDAR.MEETING_DETAIL.RSVP.DECLINED'),
      className: 'bg-n-ruby-9/10 text-n-ruby-11',
    },
    rsvp_tentative: {
      label: t('CRM_KANBAN.CALENDAR.MEETING_DETAIL.RSVP.TENTATIVE'),
      className: 'bg-n-amber-9/10 text-n-amber-11',
    },
    rsvp_pending: {
      label: t('CRM_KANBAN.CALENDAR.MEETING_DETAIL.RSVP.PENDING'),
      className: 'bg-n-alpha-2 text-n-slate-11',
    },
  };
  return map[normalized] || map.rsvp_pending;
};

const fetchMeeting = async () => {
  if (!props.show || !meetingId.value || !accountId.value) return;

  isLoading.value = true;
  loadError.value = false;
  try {
    const response = await crmMeetingsAPI.show(
      accountId.value,
      meetingId.value
    );
    detail.value = response.data.payload;
  } catch {
    loadError.value = true;
  } finally {
    isLoading.value = false;
  }
};

// On open we sync RSVP from Google first (same { payload } shape); if that
// fails we fall back to a plain fetch so the card still renders.
const syncMeeting = async ({ force = false } = {}) => {
  if (!meetingId.value || !accountId.value) return;

  try {
    const response = await crmMeetingsAPI.sync(
      accountId.value,
      meetingId.value,
      {
        force,
      }
    );
    detail.value = response.data.payload;
    loadError.value = false;
  } catch {
    await fetchMeeting();
  }
};

const onSyncOnOpen = async () => {
  if (!props.show || !meetingId.value || !accountId.value) return;

  isLoading.value = true;
  loadError.value = false;
  await syncMeeting();
  isLoading.value = false;
};

const onRefreshRsvp = async () => {
  if (isSyncing.value) return;
  isSyncing.value = true;
  await syncMeeting({ force: true });
  isSyncing.value = false;
};

watch([() => props.show, meetingId], ([isOpen]) => {
  if (isOpen) onSyncOnOpen();
  else detail.value = null;
});

const openJoinLink = () => {
  const url = location.value.joinUrl;
  if (url) window.open(url, '_blank', 'noopener,noreferrer');
};

const onOpenCard = () => emit('openCard', meeting.value);
const onReschedule = () => emit('reschedule', meeting.value);

const isCancelable = computed(() => meeting.value.status === 'scheduled');

const onCancelClick = () => cancelDialogRef.value?.open();

const onConfirmCancel = async () => {
  if (isCanceling.value || !meetingId.value || !accountId.value) return;

  isCanceling.value = true;
  try {
    const response = await crmMeetingsAPI.cancel(
      accountId.value,
      meetingId.value
    );
    detail.value = response.data?.payload || detail.value;
    cancelDialogRef.value?.close();
    useAlert(t('CRM_KANBAN.CALENDAR.MEETING_DETAIL.CANCELED_TOAST'));
    emit('canceled', meetingId.value);
    emit('close');
  } catch {
    useAlert(t('CRM_KANBAN.CALENDAR.MEETING_DETAIL.ERRORS.CANCEL_FAILED'));
  } finally {
    isCanceling.value = false;
  }
};

// Outcome (S2): a scheduled meeting that already started can be marked as held
// or no-show. "Reagendou" reuses the S1 reschedule flow (no stored outcome).
const recordedOutcome = computed(() => meeting.value.outcome || null);

// The meeting must have FINISHED (end time passed), not merely started — mirrors
// the server-side guard in RecordOutcomeService so the outcome prompt and the API
// agree (no recording an in-progress or future meeting).
const isPastMeeting = computed(
  () => !!endsAt.value && endsAt.value.getTime() <= Date.now()
);

const canRecordOutcome = computed(
  () =>
    meeting.value.status === 'scheduled' &&
    isPastMeeting.value &&
    !recordedOutcome.value
);

const outcomeChipMeta = computed(() => {
  if (recordedOutcome.value === 'held') {
    return {
      label: t('CRM_KANBAN.CALENDAR.MEETING_DETAIL.OUTCOME_HELD_CHIP'),
      className: 'bg-n-teal-9/10 text-n-teal-11',
    };
  }
  if (recordedOutcome.value === 'no_show') {
    return {
      label: t('CRM_KANBAN.CALENDAR.MEETING_DETAIL.OUTCOME_NO_SHOW_CHIP'),
      className: 'bg-n-amber-9/10 text-n-amber-11',
    };
  }
  return null;
});

const outcomeRecordedAtLabel = computed(() => {
  const date = toDate(meeting.value.outcome_recorded_at);
  if (!date) return '';
  return format(date, "dd/MM/yyyy 'as' HH:mm", {
    locale: dateFnsLocale.value,
  });
});

const onRecordOutcome = async (outcome, notes) => {
  if (isRecordingOutcome.value || !meetingId.value || !accountId.value) return;

  isRecordingOutcome.value = true;
  try {
    const payload = { outcome };
    if (notes !== undefined) payload.notes = notes;
    const response = await crmMeetingsAPI.recordOutcome(
      accountId.value,
      meetingId.value,
      payload
    );
    detail.value = response.data?.payload || detail.value;
    emit('updated', detail.value);
  } catch {
    useAlert(t('CRM_KANBAN.CALENDAR.MEETING_DETAIL.ERRORS.OUTCOME_FAILED'));
  } finally {
    isRecordingOutcome.value = false;
  }
};

// Notes for a HELD meeting — the agent jots what happened, which then feeds the
// AI summary (S5). Re-uses the outcome endpoint (notes column) so no new route.
const outcomeNotes = ref('');
const isSavingNotes = ref(false);
watch(
  () => meeting.value.outcome_notes,
  value => {
    outcomeNotes.value = value || '';
  },
  { immediate: true }
);
const onSaveNotes = async () => {
  if (isSavingNotes.value) return;
  isSavingNotes.value = true;
  await onRecordOutcome('held', outcomeNotes.value);
  isSavingNotes.value = false;
};

// AI summary (S5): only offered for a HELD meeting that has outcome notes. An
// existing summary (metadata.ai_summary, surfaced as meeting.summary) renders
// without re-calling. "Resumir com IA" generates and persists it.
const aiSummary = computed(
  () => meeting.value.summary || meeting.value.metadata?.ai_summary || ''
);

const canSummarize = computed(
  () =>
    aiEnabled.value &&
    recordedOutcome.value === 'held' &&
    !!meeting.value.outcome_notes
);

const onSummarize = async () => {
  if (isSummarizing.value || !meetingId.value || !accountId.value) return;

  summarizeRequestId += 1;
  const requestId = summarizeRequestId;
  const requestMeetingId = meetingId.value;
  const requestAccountId = accountId.value;
  isSummarizing.value = true;
  try {
    const response = await crmMeetingsAPI.summarize(
      requestAccountId,
      requestMeetingId
    );
    if (
      requestId !== summarizeRequestId ||
      requestMeetingId !== meetingId.value ||
      requestAccountId !== accountId.value ||
      !props.show
    )
      return;
    if (response.data?.summary) {
      detail.value = { ...meeting.value, summary: response.data.summary };
    } else if (response.data?.ai_available === false) {
      useAlert(t('CRM_KANBAN.CALENDAR.MEETING_DETAIL.AI_UNAVAILABLE'));
    }
  } catch {
    if (
      requestId === summarizeRequestId &&
      requestMeetingId === meetingId.value &&
      requestAccountId === accountId.value &&
      props.show
    )
      useAlert(t('CRM_KANBAN.CALENDAR.MEETING_DETAIL.AI_UNAVAILABLE'));
  } finally {
    if (requestId === summarizeRequestId) isSummarizing.value = false;
  }
};

onBeforeUnmount(() => {
  summarizeRequestId += 1;
});
</script>

<!-- eslint-disable-next-line vue/no-root-v-if -->
<template>
  <div
    v-if="show"
    class="fixed inset-0 z-[70] flex items-start justify-end bg-n-alpha-black1 p-4 backdrop-blur-[2px]"
    @click.self="emit('close')"
  >
    <article
      class="flex max-h-full w-[28rem] max-w-full flex-col overflow-hidden rounded-lg border border-n-weak bg-n-surface-2 shadow-xl"
    >
      <header
        class="flex items-start justify-between gap-3 border-b border-n-weak p-4"
      >
        <div class="flex min-w-0 items-start gap-3">
          <span
            class="flex size-10 shrink-0 items-center justify-center rounded-lg bg-n-alpha-2"
          >
            <span
              class="size-5"
              :class="providerMeta.providerIcon"
              aria-hidden="true"
            />
          </span>
          <div class="min-w-0">
            <p class="mb-1 text-[11px] font-medium uppercase text-n-slate-10">
              {{ t('CRM_KANBAN.CALENDAR.MEETING_DETAIL.TITLE') }}
            </p>
            <h3 class="mb-1 truncate text-base font-medium text-n-slate-12">
              {{ meeting.title }}
            </h3>
            <p v-if="relativeStartLabel" class="mb-0 text-xs text-n-iris-11">
              {{ relativeStartLabel }}
            </p>
          </div>
        </div>
        <Button icon="i-lucide-x" slate ghost sm @click="emit('close')" />
      </header>

      <div
        v-if="isLoading"
        class="flex min-h-56 items-center justify-center p-8"
      >
        <Spinner />
      </div>

      <div
        v-else-if="loadError"
        class="flex min-h-56 flex-col items-center justify-center gap-3 p-8 text-center"
      >
        <span class="i-lucide-alert-triangle size-6 text-n-ruby-11" />
        <p class="mb-0 text-sm text-n-slate-11">
          {{ t('CRM_KANBAN.CALENDAR.MEETING_DETAIL.ERRORS.LOAD_FAILED') }}
        </p>
        <Button
          variant="outline"
          color="slate"
          size="sm"
          :label="t('CRM_KANBAN.CALENDAR.RETRY')"
          @click="fetchMeeting"
        />
      </div>

      <div v-else class="flex flex-1 flex-col gap-4 overflow-y-auto p-4">
        <div class="grid gap-2 rounded-lg bg-n-alpha-black2 p-3">
          <p class="mb-0 flex items-center gap-2 text-sm text-n-slate-12">
            <span class="i-lucide-clock size-4 text-n-slate-10" />
            <span>{{ startsAtLabel }}</span>
            <span v-if="durationLabel" class="text-n-slate-10">
              {{ durationLabel }}
            </span>
          </p>
          <p
            v-if="location.isInternal"
            class="mb-0 flex items-center gap-2 text-sm text-n-slate-12"
            data-test="meeting-location"
          >
            <span class="size-4 text-n-slate-10" :class="location.icon" />
            <span class="text-xs text-n-slate-11">
              {{ t('CRM_KANBAN.CALENDAR.MEETING_DETAIL.LOCATION_LABEL') }}
            </span>
            {{ t(location.labelKey) }}
          </p>
          <p class="mb-0 flex items-center gap-2 text-xs text-n-slate-11">
            <span class="i-lucide-globe-2 size-3.5" />
            {{ t('CRM_KANBAN.CALENDAR.TIMEZONE', { tz: userTimezone }) }}
          </p>
          <p class="mb-0 flex items-center gap-2 text-xs text-n-slate-11">
            <span class="i-lucide-circle-dot size-3.5" />
            {{ statusLabel }}
          </p>
          <p
            v-if="meeting.source === 'ai'"
            class="mb-0 flex items-center gap-2 text-xs text-n-slate-11"
            data-test="meeting-booked-by-ai"
          >
            <span class="i-lucide-sparkles size-3.5" />
            {{ t('BOOKING.AI_AGENT.BOOKED_BY_AI') }}
          </p>
        </div>

        <button
          v-if="location.joinUrl"
          type="button"
          class="inline-flex h-11 w-full items-center justify-center gap-2 rounded-lg px-4 text-sm font-medium transition-colors"
          :class="providerMeta.joinClass"
          :aria-label="t('CRM_KANBAN.CALENDAR.MEETING_DETAIL.JOIN_MEETING')"
          @click="openJoinLink"
        >
          <span
            class="size-5"
            :class="providerMeta.joinIcon"
            aria-hidden="true"
          />
          {{ t('CRM_KANBAN.CALENDAR.MEETING_DETAIL.JOIN_MEETING') }}
        </button>

        <section class="grid gap-2">
          <div class="flex items-center justify-between gap-2">
            <h4 class="mb-0 text-xs font-medium text-n-slate-11">
              {{ t('CRM_KANBAN.CALENDAR.MEETING_DETAIL.GUESTS_LABEL') }}
            </h4>
            <button
              type="button"
              class="text-n-slate-10 transition-colors hover:text-n-slate-12 disabled:opacity-50"
              :disabled="isSyncing"
              :aria-label="t('CRM_KANBAN.CALENDAR.MEETING_DETAIL.SYNC_RSVP')"
              :title="t('CRM_KANBAN.CALENDAR.MEETING_DETAIL.SYNC_RSVP')"
              @click="onRefreshRsvp"
            >
              <span
                class="i-lucide-refresh-cw block size-3.5"
                :class="{ 'animate-spin': isSyncing }"
              />
            </button>
          </div>
          <div class="grid gap-2">
            <div
              v-for="guest in guests"
              :key="guest.id || guest.email"
              class="flex items-center justify-between gap-3 rounded-lg border border-n-weak bg-n-alpha-black2 px-3 py-2"
            >
              <div class="min-w-0">
                <p class="mb-0 truncate text-sm font-medium text-n-slate-12">
                  {{ guest.name || guest.email }}
                </p>
                <p
                  v-if="guest.name && guest.email"
                  class="mb-0 truncate text-xs text-n-slate-10"
                >
                  {{ guest.email }}
                </p>
              </div>
              <span
                class="shrink-0 rounded-md px-2 py-1 text-[11px] font-medium"
                :class="rsvpMeta(guest.rsvp_status).className"
              >
                {{ rsvpMeta(guest.rsvp_status).label }}
              </span>
            </div>
          </div>
        </section>

        <section
          v-if="canRecordOutcome"
          class="grid gap-3 rounded-lg border border-n-weak bg-n-alpha-black2 p-3"
        >
          <h4 class="mb-0 text-xs font-medium text-n-slate-11">
            {{ t('CRM_KANBAN.CALENDAR.MEETING_DETAIL.OUTCOME_PROMPT') }}
          </h4>
          <div class="flex flex-wrap gap-2">
            <Button
              variant="outline"
              color="teal"
              size="sm"
              icon="i-lucide-circle-check"
              :label="t('CRM_KANBAN.CALENDAR.MEETING_DETAIL.OUTCOME_HELD')"
              :is-loading="isRecordingOutcome"
              :disabled="isRecordingOutcome"
              @click="onRecordOutcome('held')"
            />
            <Button
              variant="outline"
              color="amber"
              size="sm"
              icon="i-lucide-user-x"
              :label="t('CRM_KANBAN.CALENDAR.MEETING_DETAIL.OUTCOME_NO_SHOW')"
              :is-loading="isRecordingOutcome"
              :disabled="isRecordingOutcome"
              @click="onRecordOutcome('no_show')"
            />
            <Button
              variant="outline"
              color="slate"
              size="sm"
              icon="i-lucide-calendar-clock"
              :label="
                t('CRM_KANBAN.CALENDAR.MEETING_DETAIL.OUTCOME_RESCHEDULED')
              "
              :disabled="isRecordingOutcome"
              @click="onReschedule"
            />
          </div>
        </section>

        <section
          v-else-if="outcomeChipMeta"
          class="grid gap-2 rounded-lg border border-n-weak bg-n-alpha-black2 p-3"
        >
          <div class="flex flex-wrap items-center gap-2">
            <span
              class="shrink-0 rounded-md px-2 py-1 text-[11px] font-medium"
              :class="outcomeChipMeta.className"
            >
              {{ outcomeChipMeta.label }}
            </span>
            <span v-if="outcomeRecordedAtLabel" class="text-xs text-n-slate-10">
              {{
                t('CRM_KANBAN.CALENDAR.MEETING_DETAIL.OUTCOME_RECORDED_AT', {
                  time: outcomeRecordedAtLabel,
                })
              }}
            </span>
          </div>
          <div v-if="recordedOutcome === 'held'" class="grid gap-1.5">
            <textarea
              v-model="outcomeNotes"
              rows="3"
              :placeholder="
                t('CRM_KANBAN.CALENDAR.MEETING_DETAIL.NOTES_PLACEHOLDER')
              "
              class="w-full resize-y rounded-lg bg-n-alpha-black2 p-2 text-sm text-n-slate-12 outline outline-1 outline-n-weak placeholder:text-n-slate-10"
            />
            <div class="flex justify-end">
              <Button
                variant="faded"
                color="slate"
                size="sm"
                icon="i-lucide-save"
                :label="t('CRM_KANBAN.CALENDAR.MEETING_DETAIL.NOTES_SAVE')"
                :is-loading="isSavingNotes"
                :disabled="isSavingNotes"
                @click="onSaveNotes"
              />
            </div>
          </div>
        </section>

        <section v-if="meeting.description" class="grid gap-2">
          <h4 class="mb-0 text-xs font-medium text-n-slate-11">
            {{ t('CRM_KANBAN.CALENDAR.MEETING_DETAIL.DESCRIPTION_LABEL') }}
          </h4>
          <p
            class="mb-0 whitespace-pre-wrap rounded-lg bg-n-alpha-black2 p-3 text-sm leading-5 text-n-slate-11"
          >
            {{ meeting.description }}
          </p>
        </section>

        <section v-if="canSummarize || aiSummary" class="grid gap-2">
          <div class="flex items-center justify-between gap-2">
            <h4
              class="mb-0 flex items-center gap-1.5 text-xs font-medium text-n-slate-11"
            >
              <span
                class="i-lucide-sparkles size-3.5 text-n-iris-11"
                aria-hidden="true"
              />
              {{ t('CRM_KANBAN.CALENDAR.MEETING_DETAIL.AI_SUMMARY_TITLE') }}
            </h4>
            <Button
              v-if="canSummarize"
              variant="ghost"
              color="slate"
              size="xs"
              icon="i-lucide-sparkles"
              :label="
                aiSummary
                  ? t(
                      'CRM_KANBAN.CALENDAR.MEETING_DETAIL.AI_SUMMARY_REGENERATE'
                    )
                  : t('CRM_KANBAN.CALENDAR.MEETING_DETAIL.AI_SUMMARY_BUTTON')
              "
              :is-loading="isSummarizing"
              :disabled="isSummarizing"
              @click="onSummarize"
            />
          </div>
          <p
            v-if="aiSummary"
            class="mb-0 whitespace-pre-wrap rounded-lg border border-n-iris-5 bg-n-iris-3 p-3 text-sm leading-5 text-n-slate-12"
          >
            {{ aiSummary }}
          </p>
          <p
            v-else-if="isSummarizing"
            class="mb-0 flex items-center gap-1.5 text-xs text-n-slate-10"
          >
            <Spinner class="size-3.5" />
            {{ t('CRM_KANBAN.CALENDAR.MEETING_DETAIL.AI_SUMMARY_LOADING') }}
          </p>
        </section>
      </div>

      <footer
        class="flex flex-wrap items-center justify-between gap-2 border-t border-n-weak p-4"
      >
        <span class="flex items-center gap-1.5 text-xs text-n-slate-11">
          <span class="i-lucide-bell size-3.5" />
          {{ t('CRM_KANBAN.CALENDAR.MEETING_SCHEDULER.REMINDER_15') }}
        </span>
        <div class="flex items-center gap-2">
          <Button
            v-if="meeting.card_id"
            variant="outline"
            color="slate"
            size="sm"
            icon="i-lucide-briefcase"
            :label="t('CRM_KANBAN.CALENDAR.EVENT.OPEN_DEAL')"
            @click="onOpenCard"
          />
          <Button
            v-if="isCancelable"
            variant="outline"
            color="ruby"
            size="sm"
            icon="i-lucide-calendar-x"
            :label="t('CRM_KANBAN.CALENDAR.MEETING_DETAIL.CANCEL_MEETING')"
            @click="onCancelClick"
          />
          <Button
            v-if="isCancelable"
            variant="outline"
            color="slate"
            size="sm"
            icon="i-lucide-calendar-clock"
            :label="t('CRM_KANBAN.CALENDAR.EVENT.RESCHEDULE')"
            @click="onReschedule"
          />
        </div>
      </footer>
    </article>

    <Dialog
      ref="cancelDialogRef"
      type="alert"
      :title="t('CRM_KANBAN.CALENDAR.MEETING_DETAIL.CANCEL_CONFIRM_TITLE')"
      :description="t('CRM_KANBAN.CALENDAR.MEETING_DETAIL.CANCEL_CONFIRM_BODY')"
      :confirm-button-label="
        t('CRM_KANBAN.CALENDAR.MEETING_DETAIL.CANCEL_CONFIRM_OK')
      "
      :cancel-button-label="
        t('CRM_KANBAN.CALENDAR.MEETING_DETAIL.KEEP_MEETING')
      "
      :is-loading="isCanceling"
      :disable-confirm-button="isCanceling"
      @confirm="onConfirmCancel"
    />
  </div>
</template>
