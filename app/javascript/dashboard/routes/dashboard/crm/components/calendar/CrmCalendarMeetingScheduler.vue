<script setup>
import { computed, nextTick, ref, watch, onBeforeUnmount } from 'vue';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { format } from 'date-fns';
import { enUS, ptBR } from 'date-fns/locale';

import crmMeetingsAPI from 'dashboard/api/crmMeetings';
import Button from 'dashboard/components-next/button/Button.vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';

const props = defineProps({
  show: { type: Boolean, default: false },
  accountId: { type: [String, Number], default: null },
  cardId: { type: [String, Number], default: null },
  dealTitle: { type: String, default: '' },
  date: { type: [Date, String, Number], default: () => new Date() },
  availableInboxes: { type: Array, default: () => [] },
  cardContactEmail: { type: String, default: '' },
  cardContactName: { type: String, default: '' },
  meeting: { type: Object, default: null },
});

const emit = defineEmits(['create', 'updated', 'close', 'update:show']);

// Reschedule mode reuses this scheduler when an existing meeting is passed in:
// it prefills every field and, on submit, only PATCHes start/end/timezone.
const isReschedule = computed(() => !!props.meeting?.id);

const route = useRoute();
const { t, locale } = useI18n();

const DEFAULT_TIME = '09:00';
const DEFAULT_DURATION_MINUTES = 30;
const REMINDER_MINUTES = 15;
const TIME_PRESETS = ['09:00', '12:00', '15:00', '18:00'];
const EMAIL_PATTERN = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

const dialogRef = ref(null);
const title = ref('');
const description = ref('');
const selectedInboxId = ref('');
const pickedDate = ref('');
const selectedTime = ref(DEFAULT_TIME);
const showCustomTime = ref(false);
const duration = ref(DEFAULT_DURATION_MINUTES);
const reminderEnabled = ref(true);
const guests = ref([]);
const guestEmail = ref('');
const guestEmailError = ref('');
const showErrors = ref(false);
const isScheduling = ref(false);
const error = ref('');
// Free/busy: intervals (ms epoch) for the selected mailbox + day, used to disable
// conflicting time presets so the agent doesn't double-book.
const busyIntervals = ref([]);
const isLoadingAvailability = ref(false);
let availabilityTimer = null;
let availabilityRequestId = 0;

// AI (S5): time suggestions + invite drafting use the account's own OpenAI key.
// Affordances are hidden unless the install has CRM_AI_ENABLED on; the backend
// still enforces and degrades gracefully (suggest falls back to free slots).
const aiEnabled = computed(
  () => window.globalConfig?.CRM_AI_ENABLED === 'true'
);
const aiSuggestions = ref([]);
const isSuggestingTimes = ref(false);
const suggestionsLoaded = ref(false);
const isDraftingInvite = ref(false);
const descriptionFromAi = ref(false);
let suggestionsRequestId = 0;
let draftRequestId = 0;

const invalidateAiRequests = () => {
  suggestionsRequestId += 1;
  draftRequestId += 1;
  isSuggestingTimes.value = false;
  isDraftingInvite.value = false;
};

const pad = value => String(value).padStart(2, '0');

const toDate = value => {
  if (value instanceof Date) return new Date(value.getTime());

  if (typeof value === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(value)) {
    const [year, month, day] = value.split('-').map(Number);
    return new Date(year, month - 1, day);
  }

  const date = value ? new Date(value) : new Date();
  return Number.isNaN(date.getTime()) ? new Date() : date;
};

const toDateInput = value => {
  const date = toDate(value);
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(
    date.getDate()
  )}`;
};

const parseDateInput = value => {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value || '')) return null;

  const [year, month, day] = value.split('-').map(Number);
  return new Date(year, month - 1, day);
};

const normalizeEmail = email => email.toString().trim().toLowerCase();
const isValidEmail = email => EMAIL_PATTERN.test(normalizeEmail(email));
const generateIdempotencyKey = () =>
  window.crypto?.randomUUID?.() ||
  `${Date.now()}-${Math.random().toString(36).slice(2)}`;

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

// This account has no calendar-enabled mailbox connected — show an empty state
// guiding the user to connect one instead of an empty mailbox picker.
const hasCalendarInbox = computed(() => calendarInboxes.value.length > 0);

const isDepartmentMailbox = inbox =>
  inbox?.shared ||
  inbox?.kind === 'department' ||
  inbox?.mailbox_type === 'department' ||
  inbox?.mailboxType === 'department';

const mailboxKindLabel = inbox =>
  isDepartmentMailbox(inbox)
    ? t('CRM_KANBAN.CALENDAR.MEETING_SCHEDULER.MAILBOX_DEPARTMENT')
    : t('CRM_KANBAN.CALENDAR.MEETING_SCHEDULER.MAILBOX_PERSONAL');

const mailboxName = inbox =>
  inbox?.calendar_identity ||
  inbox?.calendarIdentity ||
  inbox?.email ||
  inbox?.name ||
  t('CRM_KANBAN.CALENDAR.MEETING_SCHEDULER.MAILBOX_FALLBACK', {
    id: inbox?.id,
  });

const mailboxOptions = computed(() =>
  calendarInboxes.value.map(inbox => ({
    value: inbox.id,
    label: `${mailboxName(inbox)} - ${mailboxKindLabel(inbox)}`,
  }))
);

const selectedInbox = computed(() =>
  calendarInboxes.value.find(
    inbox => String(inbox.id) === String(selectedInboxId.value)
  )
);

const normalizeProvider = provider => {
  const value = provider?.toString().toLowerCase() || '';
  return value.includes('microsoft') || value.includes('outlook')
    ? 'microsoft'
    : 'google';
};

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

const scheduleButtonLabel = computed(() => {
  if (isScheduling.value) {
    return isReschedule.value
      ? t('CRM_KANBAN.CALENDAR.MEETING_SCHEDULER.RESCHEDULING')
      : t('CRM_KANBAN.CALENDAR.MEETING_SCHEDULER.SCHEDULING');
  }
  return isReschedule.value
    ? t('CRM_KANBAN.CALENDAR.MEETING_SCHEDULER.RESCHEDULE_SUBMIT')
    : t('CRM_KANBAN.CALENDAR.MEETING_SCHEDULER.SCHEDULE');
});

const dealLabel = computed(
  () =>
    props.dealTitle ||
    t('CRM_KANBAN.CALENDAR.MEETING_SCHEDULER.DEAL_FALLBACK', {
      id: props.cardId,
    })
);

const validGuests = computed(() =>
  guests.value.filter(guest => isValidEmail(guest.email))
);

const hasValidTime = computed(() =>
  /^([01]\d|2[0-3]):[0-5]\d$/.test(selectedTime.value || '')
);

const userTimezone = computed(
  () => Intl.DateTimeFormat().resolvedOptions().timeZone || 'UTC'
);

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

const guestMessage = computed(
  () =>
    guestEmailError.value ||
    (showErrors.value ? validationErrors.value.guests : '')
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
  guestEmail.value = '';
  guestEmailError.value = '';
  showErrors.value = false;
  isScheduling.value = false;
  error.value = '';
  busyIntervals.value = [];
  aiSuggestions.value = [];
  suggestionsLoaded.value = false;
  descriptionFromAi.value = false;
};

const resetForm = () => {
  invalidateAiRequests();
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
  guestEmail.value = '';
  guestEmailError.value = '';
  showErrors.value = false;
  isScheduling.value = false;
  error.value = '';
  busyIntervals.value = [];
  aiSuggestions.value = [];
  suggestionsLoaded.value = false;
  descriptionFromAi.value = false;
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

// AI suggested-time chip: "HH:mm" label parsed from the ISO start, plus the LLM
// reason (falls back to "free on calendar") shown as the tooltip.
const suggestionTimeLabel = isoString => {
  const date = new Date(isoString);
  if (Number.isNaN(date.getTime())) return '';
  return `${pad(date.getHours())}:${pad(date.getMinutes())}`;
};

const suggestionReason = reason =>
  reason || t('CRM_KANBAN.CALENDAR.MEETING_SCHEDULER.AI_SUGGESTION_REASON');

const onSuggestTimes = async () => {
  if (
    isSuggestingTimes.value ||
    !aiEnabled.value ||
    !selectedInbox.value ||
    !parseDateInput(pickedDate.value) ||
    !currentAccountId.value ||
    !props.cardId
  ) {
    return;
  }

  suggestionsRequestId += 1;
  const requestId = suggestionsRequestId;
  const requestContext = {
    accountId: currentAccountId.value,
    cardId: props.cardId,
    inboxId: selectedInboxId.value,
    date: pickedDate.value,
    duration: Number(duration.value),
    timezone: userTimezone.value,
  };
  isSuggestingTimes.value = true;
  suggestionsLoaded.value = false;
  try {
    const { data } = await crmMeetingsAPI.suggestTimes(
      requestContext.accountId,
      {
        cardId: requestContext.cardId,
        inboxId: requestContext.inboxId,
        date: requestContext.date,
        durationMinutes: requestContext.duration,
        timezone: requestContext.timezone,
      }
    );
    if (
      requestId !== suggestionsRequestId ||
      requestContext.accountId !== currentAccountId.value ||
      requestContext.cardId !== props.cardId ||
      requestContext.inboxId !== selectedInboxId.value ||
      requestContext.date !== pickedDate.value ||
      requestContext.duration !== Number(duration.value) ||
      requestContext.timezone !== userTimezone.value
    )
      return;
    aiSuggestions.value = (data?.suggestions || []).filter(s => s?.starts_at);
  } catch (exception) {
    if (
      requestId === suggestionsRequestId &&
      requestContext.accountId === currentAccountId.value &&
      requestContext.cardId === props.cardId &&
      requestContext.inboxId === selectedInboxId.value &&
      requestContext.date === pickedDate.value &&
      requestContext.duration === Number(duration.value) &&
      requestContext.timezone === userTimezone.value
    )
      aiSuggestions.value = [];
  } finally {
    if (requestId === suggestionsRequestId) {
      suggestionsLoaded.value = true;
      isSuggestingTimes.value = false;
    }
  }
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

const onDraftInvite = async () => {
  if (
    isDraftingInvite.value ||
    !aiEnabled.value ||
    !currentAccountId.value ||
    !props.cardId
  ) {
    return;
  }

  draftRequestId += 1;
  const requestId = draftRequestId;
  const requestContext = {
    accountId: currentAccountId.value,
    cardId: props.cardId,
    title: title.value.trim(),
    description: description.value,
  };
  isDraftingInvite.value = true;
  try {
    const { data } = await crmMeetingsAPI.draftInvite(
      requestContext.accountId,
      {
        cardId: requestContext.cardId,
        title: requestContext.title,
      }
    );
    if (
      requestId !== draftRequestId ||
      requestContext.accountId !== currentAccountId.value ||
      requestContext.cardId !== props.cardId ||
      requestContext.title !== title.value.trim() ||
      requestContext.description !== description.value
    )
      return;
    if (data?.description) {
      description.value = data.description;
      descriptionFromAi.value = true;
    }
  } catch (exception) {
    // Fail-safe: leave the description untouched; backend never 500s.
  } finally {
    if (requestId === draftRequestId) isDraftingInvite.value = false;
  }
};

const addGuest = () => {
  const email = normalizeEmail(guestEmail.value);
  guestEmailError.value = '';

  if (!email) {
    guestEmailError.value = t(
      'CRM_KANBAN.CALENDAR.MEETING_SCHEDULER.GUEST_EMAIL_REQUIRED'
    );
    return;
  }

  if (!isValidEmail(email)) {
    guestEmailError.value = t(
      'CRM_KANBAN.CALENDAR.MEETING_SCHEDULER.GUEST_EMAIL_INVALID'
    );
    return;
  }

  if (guests.value.some(guest => normalizeEmail(guest.email) === email)) {
    guestEmailError.value = t(
      'CRM_KANBAN.CALENDAR.MEETING_SCHEDULER.GUEST_EMAIL_DUPLICATE'
    );
    return;
  }

  guests.value = [...guests.value, { email, name: '', source: 'external' }];
  guestEmail.value = '';
};

// Keys that confirm the typed email as a chip — captured on keydown (before the
// browser's default submit/focus shift) so Enter no longer "leaks" into the form
// and pops the mailbox combo open. Comma/semicolon mirror Gmail's guest field.
const GUEST_COMMIT_KEYS = ['Enter', ',', ';'];
const onGuestKeydown = event => {
  if (!GUEST_COMMIT_KEYS.includes(event.key)) return;
  event.preventDefault();
  event.stopPropagation();
  addGuest();
};

// Leaving the field with a valid, unique email commits it silently (no nagging
// error on blur) — so clicking elsewhere never loses what was typed.
const onGuestBlur = () => {
  const email = normalizeEmail(guestEmail.value);
  if (!email || !isValidEmail(email)) return;

  if (!guests.value.some(guest => normalizeEmail(guest.email) === email)) {
    guests.value = [...guests.value, { email, name: '', source: 'external' }];
  }
  guestEmail.value = '';
  guestEmailError.value = '';
};

// Safety net on submit: commit any email still sitting in the field. Returns false
// (and surfaces the error) only when the leftover text is a non-empty INVALID email,
// so nothing the user typed is ever silently dropped when they hit "Agendar".
const commitPendingGuest = () => {
  const raw = guestEmail.value.trim();
  if (!raw) return true;

  const email = normalizeEmail(raw);
  if (!isValidEmail(email)) {
    guestEmailError.value = t(
      'CRM_KANBAN.CALENDAR.MEETING_SCHEDULER.GUEST_EMAIL_INVALID'
    );
    return false;
  }

  if (!guests.value.some(guest => normalizeEmail(guest.email) === email)) {
    guests.value = [...guests.value, { email, name: '', source: 'external' }];
  }
  guestEmail.value = '';
  return true;
};

const removeGuest = email => {
  const normalizedEmail = normalizeEmail(email);
  guests.value = guests.value.filter(
    guest => normalizeEmail(guest.email) !== normalizedEmail
  );
};

const guestInitials = guest => {
  const source = guest.name || guest.email;
  return source
    .split(/[ @._-]/)
    .filter(Boolean)
    .slice(0, 2)
    .map(part => part[0])
    .join('')
    .toUpperCase();
};

const buildStartsAt = () => {
  const date = parseDateInput(pickedDate.value);
  if (!date || !hasValidTime.value) return null;

  const [hour, minute] = selectedTime.value.split(':').map(Number);
  date.setHours(hour, minute, 0, 0);
  return date;
};

const toIso8601WithOffset = date => {
  const offset = -date.getTimezoneOffset();
  const sign = offset >= 0 ? '+' : '-';
  const absOffset = Math.abs(offset);

  return [
    `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`,
    `T${pad(date.getHours())}:${pad(date.getMinutes())}:${pad(
      date.getSeconds()
    )}`,
    `${sign}${pad(Math.floor(absOffset / 60))}:${pad(absOffset % 60)}`,
  ].join('');
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

const onSchedule = async () => {
  if (isScheduling.value) return;

  guestEmailError.value = '';
  // Commit a still-typed guest before validating — blocks only on invalid text.
  if (!commitPendingGuest()) return;

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
    emit('update:show', false);
    emit('close');
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

const onClose = () => {
  if (isScheduling.value) return;
  emit('update:show', false);
  emit('close');
};

watch(
  () => props.show,
  isOpen => {
    if (isOpen) {
      resetForm();
      nextTick(() => dialogRef.value?.open());
      fetchAvailability();
    } else {
      invalidateAiRequests();
      dialogRef.value?.close();
    }
  }
);

// Re-fetch availability whenever the mailbox or day changes (debounced) so the
// busy markings always reflect the current selection.
watch([pickedDate, selectedInboxId], () => {
  invalidateAiRequests();
  if (props.show) scheduleAvailabilityFetch();
  // Suggestions are tied to the mailbox + day; drop them when either changes so a
  // stale chip can't be picked against a different context.
  aiSuggestions.value = [];
  suggestionsLoaded.value = false;
});

watch(
  calendarInboxes,
  () => {
    if (!selectedInbox.value) selectedInboxId.value = preferredInboxId();
  },
  { immediate: true }
);

watch([() => props.cardId, currentAccountId], invalidateAiRequests);

onBeforeUnmount(() => {
  if (availabilityTimer) clearTimeout(availabilityTimer);
  availabilityRequestId += 1;
  invalidateAiRequests();
});
</script>

<template>
  <Dialog
    ref="dialogRef"
    :title="
      isReschedule
        ? t('CRM_KANBAN.CALENDAR.MEETING_SCHEDULER.RESCHEDULE_TITLE')
        : t('CRM_KANBAN.CALENDAR.MEETING_SCHEDULER.TITLE')
    "
    width="md"
    overflow-y-auto
    :show-cancel-button="false"
    :show-confirm-button="false"
    @confirm="onSchedule"
    @close="onClose"
  >
    <div class="flex flex-col gap-4">
      <p class="-mt-2 mb-0 flex items-center gap-1.5 text-xs text-n-slate-11">
        <span class="i-lucide-briefcase size-3.5" />
        <span>{{
          t('CRM_KANBAN.CALENDAR.MEETING_SCHEDULER.DEAL', { deal: dealLabel })
        }}</span>
      </p>

      <div
        v-if="!hasCalendarInbox"
        class="flex flex-col items-center gap-2 rounded-lg bg-n-alpha-1 px-4 py-8 text-center outline outline-1 outline-n-weak"
      >
        <span
          class="i-lucide-calendar-x size-8 text-n-slate-10"
          aria-hidden="true"
        />
        <p class="mb-0 text-sm font-medium text-n-slate-12">
          {{ t('CRM_KANBAN.CALENDAR.MEETING_SCHEDULER.NO_MAILBOX_TITLE') }}
        </p>
        <p class="mb-0 max-w-xs text-xs text-n-slate-11">
          {{ t('CRM_KANBAN.CALENDAR.MEETING_SCHEDULER.NO_MAILBOX_DESC') }}
        </p>
      </div>

      <template v-else>
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
          :message-type="
            showErrors && validationErrors.title ? 'error' : 'info'
          "
          autofocus
        />

        <div class="flex flex-col gap-1.5">
          <div class="flex items-center justify-between gap-2">
            <span class="text-xs font-medium text-n-slate-11">
              {{ t('CRM_KANBAN.CALENDAR.MEETING_SCHEDULER.DESCRIPTION_LABEL') }}
            </span>
            <Button
              v-if="aiEnabled"
              type="button"
              variant="ghost"
              color="slate"
              size="xs"
              icon="i-lucide-sparkles"
              :label="
                t('CRM_KANBAN.CALENDAR.MEETING_SCHEDULER.AI_DRAFT_BUTTON')
              "
              :is-loading="isDraftingInvite"
              :disabled="isDraftingInvite"
              @click="onDraftInvite"
            />
          </div>
          <Input
            v-model="description"
            :placeholder="
              t('CRM_KANBAN.CALENDAR.MEETING_SCHEDULER.DESCRIPTION_PLACEHOLDER')
            "
          />
          <p
            v-if="descriptionFromAi"
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

        <fieldset class="flex flex-col gap-2">
          <legend
            class="mb-0 text-xs font-medium text-n-slate-11 after:ml-0.5 after:text-n-ruby-11 after:content-['*']"
          >
            {{ t('CRM_KANBAN.CALENDAR.MEETING_SCHEDULER.GUESTS_LABEL') }}
          </legend>

          <div class="flex flex-wrap gap-2">
            <span
              v-for="guest in guests"
              :key="guest.email"
              class="inline-flex max-w-full items-center gap-2 rounded-lg bg-n-alpha-1 px-2 py-1 text-xs text-n-slate-12 outline outline-1 outline-n-weak"
            >
              <span
                class="flex size-5 flex-shrink-0 items-center justify-center rounded-full bg-n-alpha-2 text-[10px] font-semibold uppercase text-n-slate-11"
              >
                {{ guestInitials(guest) }}
              </span>
              <span class="min-w-0 truncate">{{
                guest.name || guest.email
              }}</span>
              <span
                class="rounded-md bg-n-alpha-2 px-1.5 py-0.5 text-[10px] text-n-slate-11"
              >
                {{
                  guest.source === 'contact'
                    ? t('CRM_KANBAN.CALENDAR.MEETING_SCHEDULER.CONTACT_TAG')
                    : t('CRM_KANBAN.CALENDAR.MEETING_SCHEDULER.GUEST_TAG')
                }}
              </span>
              <button
                type="button"
                class="i-lucide-x size-3.5 flex-shrink-0 text-n-slate-10 hover:text-n-ruby-10"
                :aria-label="
                  t('CRM_KANBAN.CALENDAR.MEETING_SCHEDULER.REMOVE_GUEST', {
                    email: guest.email,
                  })
                "
                @click="removeGuest(guest.email)"
              />
            </span>
          </div>

          <div class="flex items-start gap-2" @keydown="onGuestKeydown">
            <Input
              v-model="guestEmail"
              type="email"
              :placeholder="
                t(
                  'CRM_KANBAN.CALENDAR.MEETING_SCHEDULER.GUEST_EMAIL_PLACEHOLDER'
                )
              "
              :message="guestMessage"
              :message-type="guestMessage ? 'error' : 'info'"
              autocomplete="email"
              class="min-w-0 flex-1"
              @blur="onGuestBlur"
            />
            <Button
              type="button"
              variant="faded"
              color="slate"
              size="md"
              icon="i-lucide-plus"
              :label="t('CRM_KANBAN.CALENDAR.MEETING_SCHEDULER.ADD_GUEST')"
              @mousedown.prevent
              @click="addGuest"
            />
          </div>

          <p class="mb-0 flex items-center gap-1.5 text-xs text-n-slate-10">
            <span
              class="i-lucide-corner-down-left size-3.5"
              aria-hidden="true"
            />
            <span>{{
              t('CRM_KANBAN.CALENDAR.MEETING_SCHEDULER.GUEST_HINT')
            }}</span>
          </p>
        </fieldset>

        <div class="grid grid-cols-1 gap-3 md:grid-cols-[1fr_11rem]">
          <Input
            v-model="pickedDate"
            type="date"
            :label="t('CRM_KANBAN.CALENDAR.MEETING_SCHEDULER.DATE_LABEL')"
            :message="showErrors ? validationErrors.date : selectedDateLabel"
            :message-type="
              showErrors && validationErrors.date ? 'error' : 'info'
            "
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
              class="inline-flex items-center gap-1 rounded-lg px-2.5 py-1 text-xs font-medium tabular-nums outline outline-1 transition-colors"
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
              class="rounded-lg px-2.5 py-1 text-xs font-medium outline outline-1 transition-colors"
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
              {{
                t('CRM_KANBAN.CALENDAR.MEETING_SCHEDULER.AVAILABILITY_LOADING')
              }}
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

          <div v-if="aiEnabled" class="mt-1 flex flex-col gap-1.5">
            <div class="flex flex-wrap items-center gap-2">
              <Button
                type="button"
                variant="ghost"
                color="slate"
                size="xs"
                icon="i-lucide-sparkles"
                :label="
                  t('CRM_KANBAN.CALENDAR.MEETING_SCHEDULER.AI_SUGGEST_BUTTON')
                "
                :is-loading="isSuggestingTimes"
                :disabled="isSuggestingTimes"
                @click="onSuggestTimes"
              />
              <span v-if="isSuggestingTimes" class="text-xs text-n-slate-10">
                {{
                  t('CRM_KANBAN.CALENDAR.MEETING_SCHEDULER.AI_SUGGEST_LOADING')
                }}
              </span>
            </div>

            <div
              v-if="aiSuggestions.length"
              class="flex flex-wrap items-center gap-2"
            >
              <span
                class="i-lucide-sparkles size-3.5 text-n-iris-11"
                aria-hidden="true"
              />
              <button
                v-for="suggestion in aiSuggestions"
                :key="suggestion.starts_at"
                type="button"
                :title="suggestionReason(suggestion.reason)"
                class="inline-flex items-center gap-1 rounded-lg bg-n-iris-3 px-2.5 py-1 text-xs font-medium tabular-nums text-n-iris-11 outline outline-1 outline-n-iris-5 transition-colors hover:bg-n-iris-4"
                @click="onPickSuggestion(suggestion)"
              >
                {{ suggestionTimeLabel(suggestion.starts_at) }}
              </button>
            </div>

            <p
              v-else-if="suggestionsLoaded && !isSuggestingTimes"
              class="mb-0 text-xs text-n-slate-10"
            >
              {{ t('CRM_KANBAN.CALENDAR.MEETING_SCHEDULER.AI_SUGGEST_EMPTY') }}
            </p>
          </div>
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
              {{
                t('CRM_KANBAN.CALENDAR.MEETING_SCHEDULER.REMINDER_15_TOGGLE')
              }}
            </p>
            <p class="mb-0 text-xs text-n-slate-11">
              {{ t('CRM_KANBAN.CALENDAR.MEETING_SCHEDULER.REMINDER_15_HINT') }}
            </p>
          </div>
          <Switch v-model="reminderEnabled" />
        </div>
      </template>
    </div>

    <template #footer>
      <div
        class="flex w-full flex-col gap-3 md:flex-row md:items-center md:justify-between"
      >
        <p
          v-if="hasCalendarInbox"
          class="mb-0 flex items-center gap-1.5 text-xs text-n-slate-11"
        >
          <span class="i-lucide-mail-check size-3.5" aria-hidden="true" />
          <span>{{
            t('CRM_KANBAN.CALENDAR.MEETING_SCHEDULER.INVITE_MICROCOPY')
          }}</span>
        </p>
        <div class="flex items-center justify-end gap-2">
          <Button
            type="button"
            variant="faded"
            color="slate"
            size="sm"
            :label="t('CRM_KANBAN.CALENDAR.MEETING_SCHEDULER.CANCEL')"
            :disabled="isScheduling"
            @click="onClose"
          />
          <Button
            v-if="hasCalendarInbox"
            type="submit"
            variant="solid"
            color="blue"
            size="sm"
            :icon="
              isReschedule
                ? 'i-lucide-calendar-clock'
                : 'i-lucide-calendar-plus'
            "
            :label="scheduleButtonLabel"
            :is-loading="isScheduling"
            :disabled="isScheduling"
          />
        </div>
      </div>
    </template>
  </Dialog>
</template>

<style scoped>
/* Tailwind-only component; scoped block kept for the scheduler SFC contract. */
</style>
