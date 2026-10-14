<script setup>
// O formulário do Google/Microsoft (convite por e-mail, vídeo automático e
// lembrete de 15 min). Mora fora da janela do calendário para o card do funil
// (#1423) marcar dentro da própria gaveta, com a mesma lógica: a janela
// (CrmCalendarMeetingScheduler) e a tela "Marcar reunião" do card usam este
// mesmo formulário. Quem usa chama `submit()` pelo próprio botão e ouve
// `create` (ou `updated`, ao remarcar) e `saving`.
import { computed, ref, watch, onBeforeUnmount } from 'vue';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { format } from 'date-fns';
import { enUS, ptBR } from 'date-fns/locale';

import crmMeetingsAPI from 'dashboard/api/crmMeetings';
import Button from 'dashboard/components-next/button/Button.vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';
import {
  pad,
  parseDateInput,
  toDateInput,
  toIso8601WithOffset,
} from './meetingDates';
import { useMeetingAi } from './useMeetingAi';
import {
  generateIdempotencyKey,
  isDepartmentMailbox,
  isValidEmail,
  mailboxLabel,
  normalizeEmail,
  normalizeProvider,
} from './meetingGuests';
import CrmMeetingGuests from './CrmMeetingGuests.vue';
import CrmMeetingAiTimes from './CrmMeetingAiTimes.vue';

const props = defineProps({
  // Ligado quando a tela aparece: limpa o formulário e busca a agenda livre.
  active: { type: Boolean, default: false },
  accountId: { type: [String, Number], default: null },
  cardId: { type: [String, Number], default: null },
  date: { type: [Date, String, Number], default: () => new Date() },
  availableInboxes: { type: Array, default: () => [] },
  cardContactEmail: { type: String, default: '' },
  cardContactName: { type: String, default: '' },
  meeting: { type: Object, default: null },
});

const emit = defineEmits(['create', 'updated', 'saving']);

// Reschedule mode reuses this scheduler when an existing meeting is passed in:
// it prefills every field and, on submit, only PATCHes start/end/timezone.
const isReschedule = computed(() => !!props.meeting?.id);

const route = useRoute();
const { t, locale } = useI18n();

const DEFAULT_TIME = '09:00';
const DEFAULT_DURATION_MINUTES = 30;
const REMINDER_MINUTES = 15;
const TIME_PRESETS = ['09:00', '12:00', '15:00', '18:00'];

const title = ref('');
const description = ref('');
const selectedInboxId = ref('');
const pickedDate = ref('');
const selectedTime = ref(DEFAULT_TIME);
const showCustomTime = ref(false);
const duration = ref(DEFAULT_DURATION_MINUTES);
const reminderEnabled = ref(true);
const guests = ref([]);
const guestsRef = ref(null);
const showErrors = ref(false);
const isScheduling = ref(false);
const error = ref('');
// Free/busy: intervals (ms epoch) for the selected mailbox + day, used to disable
// conflicting time presets so the agent doesn't double-book.
const busyIntervals = ref([]);
const isLoadingAvailability = ref(false);
let availabilityTimer = null;
let availabilityRequestId = 0;

const currentAccountId = computed(
  () => props.accountId || route.params.accountId
);

const dateFnsLocale = computed(() => (locale.value === 'pt_BR' ? ptBR : enUS));

const selectedDateLabel = computed(() => {
  const date = parseDateInput(pickedDate.value);
  if (!date) return '';
  return format(date, 'PPPP', { locale: dateFnsLocale.value });
});

const durationOptions = computed(() => [
  {
    value: 15,
    label: t('CRM_KANBAN.CALENDAR.MEETING_SCHEDULER.DURATION_15MIN'),
  },
  {
    value: 30,
    label: t('CRM_KANBAN.CALENDAR.MEETING_SCHEDULER.DURATION_30MIN'),
  },
  {
    value: 45,
    label: t('CRM_KANBAN.CALENDAR.MEETING_SCHEDULER.DURATION_45MIN'),
  },
  {
    value: 60,
    label: t('CRM_KANBAN.CALENDAR.MEETING_SCHEDULER.DURATION_1H'),
  },
]);

const timeOptions = computed(() => {
  const options = [];
  for (let hour = 0; hour < 24; hour += 1) {
    for (let minute = 0; minute < 60; minute += 15) {
      const value = `${pad(hour)}:${pad(minute)}`;
      options.push({ value, label: value });
    }
  }
  return options;
});

const calendarInboxes = computed(() =>
  (props.availableInboxes || []).filter(
    inbox => inbox.calendar_enabled || inbox.calendarEnabled
  )
);

const mailboxOptions = computed(() =>
  calendarInboxes.value.map(inbox => ({
    value: inbox.id,
    label: mailboxLabel(t, inbox),
  }))
);

const selectedInbox = computed(() =>
  calendarInboxes.value.find(
    inbox => String(inbox.id) === String(selectedInboxId.value)
  )
);

const selectedProvider = computed(() =>
  selectedInbox.value ? normalizeProvider(selectedInbox.value.provider) : ''
);

const providerLabel = computed(() => {
  if (!selectedProvider.value) {
    return t('CRM_KANBAN.CALENDAR.MEETING_SCHEDULER.PROVIDER_PLACEHOLDER');
  }

  return selectedProvider.value === 'microsoft'
    ? t('CRM_KANBAN.PROVIDERS.TEAMS')
    : t('CRM_KANBAN.PROVIDERS.GOOGLE_MEET');
});

const mailboxProviderIcon = computed(() =>
  selectedProvider.value === 'microsoft'
    ? 'i-logos-microsoft-icon'
    : 'i-logos-google-icon'
);

const onlineMeetingIcon = computed(() => {
  if (!selectedProvider.value) return 'i-lucide-video';
  return selectedProvider.value === 'microsoft'
    ? 'i-logos-microsoft-teams'
    : 'i-logos-google-meet';
});

const validGuests = computed(() =>
  guests.value.filter(guest => isValidEmail(guest.email))
);

const hasValidTime = computed(() =>
  /^([01]\d|2[0-3]):[0-5]\d$/.test(selectedTime.value || '')
);

const userTimezone = computed(
  () => Intl.DateTimeFormat().resolvedOptions().timeZone || 'UTC'
);

const ai = useMeetingAi({
  t,
  accountId: currentAccountId,
  cardId: computed(() => props.cardId),
  inboxId: selectedInboxId,
  date: pickedDate,
  duration,
  timezone: userTimezone,
  title,
  description,
  podeSugerir: computed(
    () =>
      Boolean(selectedInbox.value) && Boolean(parseDateInput(pickedDate.value))
  ),
});

// Epoch (ms) for a HH:mm slot on the picked date, in the user's local zone — the
// same basis the busy intervals are compared against (both local Date math).
const slotRangeFor = time => {
  const date = parseDateInput(pickedDate.value);
  if (!date || !/^([01]\d|2[0-3]):[0-5]\d$/.test(time || '')) return null;

  const [hour, minute] = time.split(':').map(Number);
  date.setHours(hour, minute, 0, 0);
  const start = date.getTime();
  return { start, end: start + Number(duration.value) * 60 * 1000 };
};

// A slot is busy when [start, end) overlaps any fetched busy interval.
const isSlotBusy = time => {
  const range = slotRangeFor(time);
  if (!range) return false;

  return busyIntervals.value.some(
    interval => range.start < interval.end && range.end > interval.start
  );
};

const selectedTimeBusy = computed(() => isSlotBusy(selectedTime.value));

const fetchAvailability = async () => {
  const date = pickedDate.value;
  const inboxId = selectedInboxId.value;

  if (!inboxId || !parseDateInput(date) || !currentAccountId.value) {
    busyIntervals.value = [];
    return;
  }

  availabilityRequestId += 1;
  const requestId = availabilityRequestId;
  isLoadingAvailability.value = true;

  try {
    const { data } = await crmMeetingsAPI.getAvailability(
      currentAccountId.value,
      { inboxId, date, timezone: userTimezone.value }
    );
    // Drop stale responses if the user changed inbox/date meanwhile.
    if (requestId !== availabilityRequestId) return;

    busyIntervals.value = (data?.payload?.busy || [])
      .map(slot => ({
        start: new Date(slot.start).getTime(),
        end: new Date(slot.end).getTime(),
      }))
      .filter(slot => !Number.isNaN(slot.start) && !Number.isNaN(slot.end));
  } catch (exception) {
    if (requestId === availabilityRequestId) busyIntervals.value = [];
  } finally {
    if (requestId === availabilityRequestId)
      isLoadingAvailability.value = false;
  }
};

const scheduleAvailabilityFetch = () => {
  if (availabilityTimer) clearTimeout(availabilityTimer);
  availabilityTimer = setTimeout(fetchAvailability, 250);
};

const validationErrors = computed(() => ({
  title: title.value.trim()
    ? ''
    : t('CRM_KANBAN.CALENDAR.MEETING_SCHEDULER.VALIDATION_TITLE'),
  inbox: selectedInbox.value
    ? ''
    : t('CRM_KANBAN.CALENDAR.MEETING_SCHEDULER.VALIDATION_MAILBOX'),
  guests: validGuests.value.length
    ? ''
    : t('CRM_KANBAN.CALENDAR.MEETING_SCHEDULER.VALIDATION_GUESTS'),
  date: parseDateInput(pickedDate.value)
    ? ''
    : t('CRM_KANBAN.CALENDAR.MEETING_SCHEDULER.VALIDATION_DATE'),
  duration:
    Number(duration.value) > 0
      ? ''
      : t('CRM_KANBAN.CALENDAR.MEETING_SCHEDULER.VALIDATION_DURATION'),
  time: hasValidTime.value
    ? ''
    : t('CRM_KANBAN.CALENDAR.MEETING_SCHEDULER.VALIDATION_TIME'),
}));

const hasValidationErrors = computed(() =>
  Object.values(validationErrors.value).some(Boolean)
);

const buildInitialGuests = () => {
  const email = normalizeEmail(props.cardContactEmail || '');
  if (!email) return [];

  return [
    {
      email,
      name: props.cardContactName || '',
      source: 'contact',
    },
  ];
};

const preferredInboxId = () => {
  const personalInbox =
    calendarInboxes.value.find(inbox => !isDepartmentMailbox(inbox)) ||
    calendarInboxes.value[0];

  return personalInbox?.id || '';
};

const guestsFromMeeting = meeting =>
  (meeting.guests || [])
    .filter(guest => guest.email)
    .map(guest => ({
      email: normalizeEmail(guest.email),
      name: guest.name || '',
      source: guest.guest_type === 'contact_guest' ? 'contact' : 'external',
    }));

// In reschedule mode every field is prefilled from the existing meeting; on
// submit only start/end/timezone are sent, so the other fields are informative.
const hydrateFromMeeting = meeting => {
  const startsAt = meeting.starts_at ? new Date(meeting.starts_at) : null;
  const endsAt = meeting.ends_at ? new Date(meeting.ends_at) : null;

  title.value = meeting.title || '';
  description.value = meeting.description || '';
  selectedInboxId.value = meeting.inbox_id || preferredInboxId();
  pickedDate.value = startsAt ? toDateInput(startsAt) : toDateInput(props.date);
  selectedTime.value = startsAt
    ? `${pad(startsAt.getHours())}:${pad(startsAt.getMinutes())}`
    : DEFAULT_TIME;
  showCustomTime.value = !TIME_PRESETS.includes(selectedTime.value);
  duration.value =
    startsAt && endsAt
      ? Math.max(Math.round((endsAt - startsAt) / 60000), 15)
      : DEFAULT_DURATION_MINUTES;
  reminderEnabled.value = !!meeting.reminder_id;
  guests.value = guestsFromMeeting(meeting);
  guestsRef.value?.reset();
  showErrors.value = false;
  isScheduling.value = false;
  error.value = '';
  busyIntervals.value = [];
  ai.clear();
};

const resetForm = () => {
  ai.invalidate();
  if (isReschedule.value) {
    hydrateFromMeeting(props.meeting);
    return;
  }

  title.value = '';
  description.value = '';
  selectedInboxId.value = preferredInboxId();
  pickedDate.value = toDateInput(props.date);
  selectedTime.value = DEFAULT_TIME;
  showCustomTime.value = false;
  duration.value = DEFAULT_DURATION_MINUTES;
  reminderEnabled.value = true;
  guests.value = buildInitialGuests();
  guestsRef.value?.reset();
  showErrors.value = false;
  isScheduling.value = false;
  error.value = '';
  busyIntervals.value = [];
  ai.clear();
};

const onInboxSelected = value => {
  selectedInboxId.value = value;
  error.value = '';
};

const onPresetTime = value => {
  selectedTime.value = value;
  showCustomTime.value = false;
};

const onCustomTime = () => {
  showCustomTime.value = true;
};

// Picking a suggestion sets the date (in case it differs) and the time.
const onPickSuggestion = suggestion => {
  const date = new Date(suggestion.starts_at);
  if (Number.isNaN(date.getTime())) return;

  pickedDate.value = toDateInput(date);
  const time = `${pad(date.getHours())}:${pad(date.getMinutes())}`;
  selectedTime.value = time;
  showCustomTime.value = !TIME_PRESETS.includes(time);
};

const buildStartsAt = () => {
  const date = parseDateInput(pickedDate.value);
  if (!date || !hasValidTime.value) return null;

  const [hour, minute] = selectedTime.value.split(':').map(Number);
  date.setHours(hour, minute, 0, 0);
  return date;
};

const buildRequestPayload = () => {
  const startsAt = buildStartsAt();
  if (!startsAt) return null;

  const endsAt = new Date(
    startsAt.getTime() + Number(duration.value) * 60 * 1000
  );
  const timezone = Intl.DateTimeFormat().resolvedOptions().timeZone || 'UTC';
  const guestEmails = validGuests.value.map(guest =>
    normalizeEmail(guest.email)
  );

  return {
    card_id: props.cardId,
    inbox_id: selectedInboxId.value,
    meeting: {
      title: title.value.trim(),
      description: description.value.trim(),
      starts_at: toIso8601WithOffset(startsAt),
      ends_at: toIso8601WithOffset(endsAt),
      timezone,
      provider: selectedProvider.value,
      reminder_minutes_before: reminderEnabled.value ? REMINDER_MINUTES : 0,
      extra_guests: guestEmails,
    },
  };
};

const submit = async () => {
  if (isScheduling.value) return;

  // Commit a still-typed guest before validating — blocks only on invalid text.
  if (guestsRef.value && !guestsRef.value.commit()) return;

  showErrors.value = true;
  error.value = '';

  if (hasValidationErrors.value || !currentAccountId.value || !props.cardId) {
    return;
  }

  const payload = buildRequestPayload();
  if (!payload) return;

  isScheduling.value = true;

  try {
    if (isReschedule.value) {
      const { data } = await crmMeetingsAPI.reschedule(
        currentAccountId.value,
        props.meeting.id,
        {
          meeting: {
            starts_at: payload.meeting.starts_at,
            ends_at: payload.meeting.ends_at,
            timezone: payload.meeting.timezone,
          },
        }
      );
      emit('updated', data?.payload || payload);
    } else {
      const { data } = await crmMeetingsAPI.createMeeting(
        currentAccountId.value,
        payload,
        generateIdempotencyKey()
      );
      emit('create', data?.payload || payload);
    }
  } catch (exception) {
    const responseError = exception?.response?.data?.error;
    error.value =
      responseError ||
      t('CRM_KANBAN.CALENDAR.MEETING_SCHEDULER.ERROR_WITH_PROVIDER', {
        provider: providerLabel.value,
      });
  } finally {
    isScheduling.value = false;
  }
};

watch(isScheduling, value => emit('saving', value));

watch(
  () => props.active,
  isOpen => {
    if (isOpen) {
      resetForm();
      fetchAvailability();
    } else {
      ai.invalidate();
    }
  },
  { immediate: true }
);

// Re-fetch availability whenever the mailbox or day changes (debounced) so the
// busy markings always reflect the current selection.
watch([pickedDate, selectedInboxId], () => {
  ai.invalidate();
  if (props.active) scheduleAvailabilityFetch();
  // Suggestions are tied to the mailbox + day; drop them when either changes so a
  // stale chip can't be picked against a different context.
  ai.clearSuggestions();
});

watch(
  calendarInboxes,
  () => {
    if (!selectedInbox.value) selectedInboxId.value = preferredInboxId();
  },
  { immediate: true }
);

watch([() => props.cardId, currentAccountId], ai.invalidate);

onBeforeUnmount(() => {
  if (availabilityTimer) clearTimeout(availabilityTimer);
  availabilityRequestId += 1;
  ai.invalidate();
});

defineExpose({ submit, isScheduling });
</script>

<template>
  <div class="flex flex-col gap-4" data-provider-meeting-form>
    <div
      v-if="error"
      role="alert"
      class="flex items-start gap-2 rounded-lg bg-n-ruby-3 px-3 py-2 text-sm text-n-ruby-11"
    >
      <span class="i-lucide-alert-triangle mt-0.5 size-4 flex-shrink-0" />
      <span>{{ error }}</span>
    </div>

    <Input
      v-model="title"
      :label="t('CRM_KANBAN.CALENDAR.MEETING_SCHEDULER.TITLE_LABEL')"
      :placeholder="
        t('CRM_KANBAN.CALENDAR.MEETING_SCHEDULER.TITLE_PLACEHOLDER')
      "
      :message="showErrors ? validationErrors.title : ''"
      :message-type="showErrors && validationErrors.title ? 'error' : 'info'"
      autofocus
    />

    <div class="flex flex-col gap-1.5">
      <div class="flex items-center justify-between gap-2">
        <span class="text-xs font-medium text-n-slate-11">
          {{ t('CRM_KANBAN.CALENDAR.MEETING_SCHEDULER.DESCRIPTION_LABEL') }}
        </span>
        <Button
          v-if="ai.enabled.value"
          type="button"
          variant="ghost"
          color="slate"
          size="xs"
          icon="i-lucide-sparkles"
          :label="t('CRM_KANBAN.CALENDAR.MEETING_SCHEDULER.AI_DRAFT_BUTTON')"
          :is-loading="ai.drafting.value"
          :disabled="ai.drafting.value"
          @click="ai.draft"
        />
      </div>
      <Input
        v-model="description"
        :placeholder="
          t('CRM_KANBAN.CALENDAR.MEETING_SCHEDULER.DESCRIPTION_PLACEHOLDER')
        "
      />
      <p
        v-if="ai.fromAi.value"
        class="mb-0 flex items-center gap-1.5 text-xs text-n-slate-10"
      >
        <span class="i-lucide-sparkles size-3.5" aria-hidden="true" />
        <span>{{
          t('CRM_KANBAN.CALENDAR.MEETING_SCHEDULER.AI_DRAFT_HINT')
        }}</span>
      </p>
    </div>

    <div class="flex flex-col gap-1.5">
      <span
        class="text-xs font-medium text-n-slate-11 after:ml-0.5 after:text-n-ruby-11 after:content-['*']"
      >
        {{ t('CRM_KANBAN.CALENDAR.MEETING_SCHEDULER.MAILBOX_LABEL') }}
      </span>
      <div class="flex items-center gap-2">
        <div
          class="flex h-10 w-10 flex-shrink-0 items-center justify-center rounded-lg bg-n-alpha-1 outline outline-1 outline-n-weak"
        >
          <span
            v-if="selectedInbox"
            :class="mailboxProviderIcon"
            class="size-5"
            aria-hidden="true"
          />
          <span
            v-else
            class="i-lucide-mail size-4 text-n-slate-11"
            aria-hidden="true"
          />
        </div>
        <ComboBox
          :model-value="selectedInboxId"
          :options="mailboxOptions"
          :placeholder="
            t('CRM_KANBAN.CALENDAR.MEETING_SCHEDULER.MAILBOX_PLACEHOLDER')
          "
          :empty-state="
            t('CRM_KANBAN.CALENDAR.MEETING_SCHEDULER.MAILBOX_EMPTY')
          "
          :message="showErrors ? validationErrors.inbox : ''"
          :has-error="showErrors && !!validationErrors.inbox"
          @update:model-value="onInboxSelected"
        />
      </div>
    </div>

    <CrmMeetingGuests
      ref="guestsRef"
      v-model="guests"
      :required-error="showErrors ? validationErrors.guests : ''"
    />

    <div class="grid grid-cols-1 gap-3 md:grid-cols-[1fr_11rem]">
      <Input
        v-model="pickedDate"
        type="date"
        :label="t('CRM_KANBAN.CALENDAR.MEETING_SCHEDULER.DATE_LABEL')"
        :message="showErrors ? validationErrors.date : selectedDateLabel"
        :message-type="showErrors && validationErrors.date ? 'error' : 'info'"
      />

      <div class="flex flex-col gap-1.5">
        <span class="text-xs font-medium text-n-slate-11">
          {{ t('CRM_KANBAN.CALENDAR.MEETING_SCHEDULER.DURATION_LABEL') }}
        </span>
        <ComboBox
          v-model="duration"
          :options="durationOptions"
          :message="showErrors ? validationErrors.duration : ''"
          :has-error="showErrors && !!validationErrors.duration"
        />
      </div>
    </div>

    <fieldset class="flex flex-col gap-1.5">
      <legend
        class="mb-1 text-xs font-medium text-n-slate-11 after:ml-0.5 after:text-n-ruby-11 after:content-['*']"
      >
        {{ t('CRM_KANBAN.CALENDAR.MEETING_SCHEDULER.TIME_LABEL') }}
      </legend>
      <div class="flex flex-wrap items-center gap-2">
        <button
          v-for="preset in TIME_PRESETS"
          :key="preset"
          type="button"
          :disabled="isSlotBusy(preset)"
          :aria-label="
            isSlotBusy(preset)
              ? t('CRM_KANBAN.CALENDAR.MEETING_SCHEDULER.BUSY_TOOLTIP', {
                  time: preset,
                })
              : preset
          "
          :title="
            isSlotBusy(preset)
              ? t('CRM_KANBAN.CALENDAR.MEETING_SCHEDULER.BUSY_TOOLTIP', {
                  time: preset,
                })
              : ''
          "
          class="relative inline-flex items-center gap-1 rounded-lg px-2.5 py-1 text-xs font-medium tabular-nums outline outline-1 transition-colors before:absolute before:inset-x-0 before:-inset-y-2.5"
          :class="
            isSlotBusy(preset)
              ? 'cursor-not-allowed bg-n-alpha-1 text-n-slate-9 line-through outline-n-weak opacity-70'
              : !showCustomTime && selectedTime === preset
                ? 'bg-n-brand text-white outline-n-brand'
                : 'bg-n-alpha-1 text-n-slate-11 outline-transparent hover:bg-n-alpha-2'
          "
          @click="onPresetTime(preset)"
        >
          {{ preset }}
          <span
            v-if="isSlotBusy(preset)"
            class="i-lucide-lock size-3"
            aria-hidden="true"
          />
        </button>
        <button
          type="button"
          class="relative rounded-lg px-2.5 py-1 text-xs font-medium outline outline-1 transition-colors before:absolute before:inset-x-0 before:-inset-y-2.5"
          :class="
            showCustomTime
              ? 'bg-n-brand text-white outline-n-brand'
              : 'bg-n-alpha-1 text-n-slate-11 outline-transparent hover:bg-n-alpha-2'
          "
          @click="onCustomTime"
        >
          {{ t('CRM_KANBAN.CALENDAR.MEETING_SCHEDULER.TIME_OTHER') }}
        </button>
        <span
          v-if="isLoadingAvailability"
          class="inline-flex items-center gap-1 text-xs text-n-slate-10"
        >
          <span
            class="i-lucide-loader-circle size-3 animate-spin"
            aria-hidden="true"
          />
          {{ t('CRM_KANBAN.CALENDAR.MEETING_SCHEDULER.AVAILABILITY_LOADING') }}
        </span>
      </div>
      <ComboBox
        v-if="showCustomTime"
        v-model="selectedTime"
        :options="timeOptions"
        :placeholder="
          t('CRM_KANBAN.CALENDAR.MEETING_SCHEDULER.TIME_PLACEHOLDER')
        "
        class="mt-1"
        :message="showErrors ? validationErrors.time : ''"
        :has-error="showErrors && !!validationErrors.time"
      />

      <CrmMeetingAiTimes
        v-if="ai.enabled.value"
        :suggestions="ai.suggestions.value"
        :suggesting="ai.suggesting.value"
        :loaded="ai.loaded.value"
        :time-label="ai.timeLabel"
        :reason="ai.reason"
        @suggest="ai.suggest"
        @pick="onPickSuggestion"
      />
      <p class="mb-0 flex items-center gap-1.5 text-xs text-n-slate-10">
        <span class="i-lucide-globe size-3.5" aria-hidden="true" />
        <span>{{
          t('CRM_KANBAN.CALENDAR.MEETING_SCHEDULER.TIMEZONE_HINT', {
            timezone: userTimezone,
          })
        }}</span>
      </p>
      <p
        v-if="selectedTimeBusy"
        role="alert"
        class="mb-0 flex items-center gap-1.5 text-xs text-n-amber-11"
      >
        <span class="i-lucide-alert-triangle size-3.5" aria-hidden="true" />
        <span>{{
          t('CRM_KANBAN.CALENDAR.MEETING_SCHEDULER.BUSY_WARNING')
        }}</span>
      </p>
    </fieldset>

    <div
      class="flex items-center justify-between gap-3 rounded-lg bg-n-alpha-1 px-3 py-2 outline outline-1 outline-n-weak"
    >
      <div class="flex min-w-0 items-center gap-2">
        <span
          :class="onlineMeetingIcon"
          class="size-5 flex-shrink-0"
          aria-hidden="true"
        />
        <div class="min-w-0">
          <p class="mb-0 truncate text-sm font-medium text-n-slate-12">
            {{ providerLabel }}
          </p>
          <p class="mb-0 text-xs text-n-slate-11">
            {{ t('CRM_KANBAN.CALENDAR.MEETING_SCHEDULER.VIDEO_AUTO_HINT') }}
          </p>
        </div>
      </div>
      <span
        class="inline-flex items-center gap-1 rounded-md bg-n-teal-3 px-2 py-1 text-xs font-medium text-n-teal-11"
      >
        <span class="i-lucide-check size-3.5" aria-hidden="true" />
        {{ t('CRM_KANBAN.CALENDAR.MEETING_SCHEDULER.VIDEO_AUTO_BADGE') }}
      </span>
    </div>

    <div
      class="flex items-center justify-between gap-3 rounded-lg bg-n-alpha-1 px-3 py-2"
    >
      <div class="min-w-0">
        <p class="mb-0 text-sm font-medium text-n-slate-12">
          {{ t('CRM_KANBAN.CALENDAR.MEETING_SCHEDULER.REMINDER_15_TOGGLE') }}
        </p>
        <p class="mb-0 text-xs text-n-slate-11">
          {{ t('CRM_KANBAN.CALENDAR.MEETING_SCHEDULER.REMINDER_15_HINT') }}
        </p>
      </div>
      <Switch v-model="reminderEnabled" />
    </div>
  </div>
</template>
