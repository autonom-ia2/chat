<script setup>
// Marcar pela agenda (#1265): dentro da janela "Agendar reunião", a atendente
// escolhe a página publicada, o dia e um horário livre (a mesma regra da
// página pública), e salva. A reunião sai pelo Booker do agendamento novo.
// Ação secundária: mandar o link para o cliente escolher (mesma API do botão
// Agendar da conversa, `booking_invites`).
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import crmBookingPagesAPI from 'dashboard/api/crmBookingPages';
import BookingInvitesAPI from 'dashboard/api/crmBookingInvites';
import NextButton from 'dashboard/components-next/button/Button.vue';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import { useAlert } from 'dashboard/composables';
import { copyTextToClipboard } from 'shared/helpers/clipboard';

const props = defineProps({
  pages: { type: Array, required: true },
  cardId: { type: [String, Number], default: null },
  card: { type: Object, default: null },
  // Dia em que a janela abre (AAAA-MM-DD, no fuso de quem usa).
  initialDay: { type: String, default: '' },
});

const emit = defineEmits(['booked', 'saving']);

const { t, locale } = useI18n();

const ERRORS = {
  'crm.booking_v2.slot_unavailable':
    'CRM_KANBAN.BOOKING_AGENDA.ERRORS.SLOT_TAKEN',
  'crm.booking_v2.invalid_phone': 'CRM_KANBAN.BOOKING_AGENDA.ERRORS.NO_PHONE',
  'crm.booking_v2.no_contact': 'CRM_KANBAN.BOOKING_AGENDA.ERRORS.NO_CONTACT',
  'crm.booking_v2.email_required':
    'CRM_KANBAN.BOOKING_AGENDA.ERRORS.EMAIL_REQUIRED',
  'crm.booking_v2.too_many_open':
    'CRM_KANBAN.BOOKING_AGENDA.ERRORS.TOO_MANY_OPEN',
  'crm.booking_v2.card_closed': 'CRM_KANBAN.BOOKING_AGENDA.ERRORS.CARD_CLOSED',
};
const ERROR_GENERIC = 'CRM_KANBAN.BOOKING_AGENDA.ERRORS.GENERIC';
const ERROR_CANNOT_REPLY = 'crm.booking_v2.cannot_reply';
const HTTP_UNAUTHORIZED = 401;

const pageId = ref(props.pages[0]?.id ?? '');
const day = ref('');
const duration = ref(null);
const location = ref('');
const slots = ref([]);
const nextSlot = ref(null);
const startsAt = ref('');
const notify = ref(false);
const isLoadingSlots = ref(false);
const isSaving = ref(false);
const error = ref('');
const showErrors = ref(false);
const invite = ref(null);
const isPreparingLink = ref(false);
const isSendingLink = ref(false);
let slotsRequest = 0;

const page = computed(
  () => props.pages.find(item => item.id === pageId.value) || props.pages[0]
);
const pageOptions = computed(() =>
  props.pages.map(item => ({ value: item.id, label: item.title }))
);
const durationOptions = computed(() =>
  (page.value?.durations || []).map(minutes => ({
    value: minutes,
    label: t('CRM_KANBAN.BOOKING_AGENDA.DURATION_OPTION', { minutes }),
  }))
);
const locationOptions = computed(() =>
  (page.value?.locations || []).map(item => ({
    value: item.type,
    label: item.label || item.type,
  }))
);
const locationLabel = computed(() => locationOptions.value[0]?.label || '');
const conversationId = computed(
  () => props.card?.conversation?.display_id || null
);
const contactName = computed(() => props.card?.contact?.name || '');

const pad = value => String(value).padStart(2, '0');
const toDateInput = value => {
  const date = value ? new Date(value) : new Date();
  const safe = Number.isNaN(date.getTime()) ? new Date() : date;
  return `${safe.getFullYear()}-${pad(safe.getMonth() + 1)}-${pad(safe.getDate())}`;
};
const todayInput = () => toDateInput(new Date());

// O ISO vem com o fuso da página: a hora mostrada é a dela.
const timeLabel = iso =>
  new Intl.DateTimeFormat(String(locale.value).replace('_', '-'), {
    hour: '2-digit',
    minute: '2-digit',
    timeZone: page.value?.timezone,
  }).format(new Date(iso));

const newRequestId = () =>
  window.crypto?.randomUUID?.() ||
  `${Date.now()}-${Math.random().toString(36).slice(2, 12)}`;
let requestId = newRequestId();

const resetForPage = () => {
  duration.value = page.value?.duration_minutes ?? null;
  location.value = page.value?.locations?.[0]?.type || '';
  notify.value = Boolean(page.value?.notices);
};

const loadSlots = async () => {
  if (!page.value || !day.value) return;
  slotsRequest += 1;
  const current = slotsRequest;
  isLoadingSlots.value = true;
  startsAt.value = '';
  try {
    const { data } = await crmBookingPagesAPI.slots(page.value.id, {
      date: day.value,
      duration: duration.value,
    });
    if (current !== slotsRequest) return;
    slots.value = data?.payload?.slots || [];
    nextSlot.value = data?.payload?.next_slot || null;
  } catch {
    if (current !== slotsRequest) return;
    slots.value = [];
    nextSlot.value = null;
    error.value = t('CRM_KANBAN.BOOKING_AGENDA.ERRORS.LOAD');
  } finally {
    if (current === slotsRequest) isLoadingSlots.value = false;
  }
};

// O próximo livre: o dia dele no fuso da página são os 10 primeiros caracteres.
const goToNextSlot = () => {
  if (!nextSlot.value) return;
  day.value = nextSlot.value.slice(0, 10);
};

const errorMessage = exception => {
  if (exception?.response?.status === HTTP_UNAUTHORIZED) {
    return t('CRM_KANBAN.BOOKING_AGENDA.ERRORS.FORBIDDEN');
  }
  return t(ERRORS[exception?.response?.data?.error] || ERROR_GENERIC);
};

const submit = async () => {
  if (isSaving.value) return;
  showErrors.value = true;
  error.value = '';
  if (!startsAt.value || !page.value) return;

  isSaving.value = true;
  emit('saving', true);
  try {
    const { data } = await crmBookingPagesAPI.book(page.value.id, {
      cardId: props.cardId,
      startsAt: startsAt.value,
      duration: duration.value,
      location: location.value,
      notify: notify.value,
      requestId,
    });
    requestId = newRequestId();
    emit('booked', data?.payload);
  } catch (exception) {
    error.value = errorMessage(exception);
    if (exception?.response?.status === 409) {
      requestId = newRequestId();
      loadSlots();
    }
  } finally {
    isSaving.value = false;
    emit('saving', false);
  }
};

const prepareLink = async () => {
  isPreparingLink.value = true;
  error.value = '';
  try {
    const { data } = await BookingInvitesAPI.create({
      bookingPageId: page.value?.id,
      cardId: props.cardId,
    });
    invite.value = data?.payload || null;
  } catch (exception) {
    error.value =
      exception?.response?.status === HTTP_UNAUTHORIZED
        ? t('CRM_KANBAN.BOOKING_AGENDA.ERRORS.FORBIDDEN')
        : t('CRM_KANBAN.BOOKING_AGENDA.ERRORS.LINK');
  } finally {
    isPreparingLink.value = false;
  }
};

const copyLink = async () => {
  try {
    await copyTextToClipboard(invite.value.url);
    useAlert(t('CRM_KANBAN.BOOKING_AGENDA.LINK_COPIED'));
  } catch {
    error.value = t('CRM_KANBAN.BOOKING_AGENDA.ERRORS.LINK');
    return;
  }
  try {
    await BookingInvitesAPI.copied(invite.value.id);
  } catch {
    // Só a contagem fica sem este envio; o link já está copiado.
  }
};

const sendLink = async () => {
  isSendingLink.value = true;
  error.value = '';
  try {
    await BookingInvitesAPI.deliver(invite.value.id, {
      conversationId: conversationId.value,
      text: invite.value.text,
    });
    useAlert(t('CRM_KANBAN.BOOKING_AGENDA.LINK_SENT'));
    invite.value = null;
  } catch (exception) {
    error.value =
      exception?.response?.data?.error === ERROR_CANNOT_REPLY
        ? t('CRM_KANBAN.BOOKING_AGENDA.ERRORS.CANNOT_REPLY')
        : t('CRM_KANBAN.BOOKING_AGENDA.ERRORS.LINK');
  } finally {
    isSendingLink.value = false;
  }
};

watch(
  () => props.pages,
  pages => {
    if (!pages.some(item => item.id === pageId.value)) {
      pageId.value = pages[0]?.id ?? '';
    }
  }
);
watch(pageId, resetForPage, { immediate: true });
watch([pageId, day, duration], () => {
  error.value = '';
  showErrors.value = false;
  loadSlots();
});

// Dia passado (ou nenhum) abre em hoje: a agenda não marca no passado.
day.value =
  props.initialDay && props.initialDay >= todayInput()
    ? props.initialDay
    : todayInput();

// Com o link na tela, a janela esconde o Salvar: a ação ali é enviar ou copiar.
const isShowingLink = computed(() => Boolean(invite.value));

defineExpose({ submit, isShowingLink });
</script>

<template>
  <div class="flex flex-col gap-4" data-booking-agenda>
    <div
      v-if="error"
      role="alert"
      class="flex items-start gap-2 rounded-lg bg-n-ruby-3 px-3 py-2 text-sm text-n-ruby-11"
    >
      <span
        class="i-lucide-alert-triangle mt-0.5 size-4 flex-shrink-0"
        aria-hidden="true"
      />
      <span>{{ error }}</span>
    </div>

    <div v-if="invite" class="flex flex-col gap-3" data-booking-agenda-link>
      <p class="mb-0 text-sm font-medium text-n-slate-12">
        {{ t('CRM_KANBAN.BOOKING_AGENDA.LINK_TITLE') }}
      </p>
      <p
        class="mb-0 whitespace-pre-line rounded-lg bg-n-alpha-1 px-3 py-2 text-sm text-n-slate-12 outline outline-1 outline-n-weak"
      >
        {{ invite.text }}
      </p>
      <div class="flex flex-col gap-2 sm:flex-row">
        <NextButton
          v-if="conversationId"
          type="button"
          lg
          class="w-full sm:flex-1"
          icon="i-lucide-send"
          :label="t('CRM_KANBAN.BOOKING_AGENDA.LINK_SEND')"
          :is-loading="isSendingLink"
          data-booking-agenda-link-send
          @click="sendLink"
        />
        <NextButton
          type="button"
          lg
          class="w-full sm:flex-1"
          :variant="conversationId ? 'outline' : 'solid'"
          :color="conversationId ? 'slate' : 'blue'"
          icon="i-lucide-copy"
          :label="t('CRM_KANBAN.BOOKING_AGENDA.LINK_COPY')"
          data-booking-agenda-link-copy
          @click="copyLink"
        />
      </div>
      <NextButton
        type="button"
        ghost
        slate
        class="min-h-11 self-start"
        icon="i-lucide-arrow-left"
        :label="t('CRM_KANBAN.BOOKING_AGENDA.LINK_BACK')"
        @click="invite = null"
      />
    </div>

    <template v-else>
      <p v-if="contactName" class="mb-0 text-sm text-n-slate-11">
        {{ t('CRM_KANBAN.BOOKING_AGENDA.CLIENT', { name: contactName }) }}
      </p>

      <div v-if="pageOptions.length > 1" class="flex flex-col gap-1.5">
        <span class="text-sm font-medium text-n-slate-12">
          {{ t('CRM_KANBAN.BOOKING_AGENDA.PAGE_LABEL') }}
        </span>
        <ChoiceSelect
          v-model="pageId"
          :options="pageOptions"
          :aria-label="t('CRM_KANBAN.BOOKING_AGENDA.PAGE_LABEL')"
          data-booking-agenda-page
        />
      </div>

      <Input
        v-model="day"
        type="date"
        :min="todayInput()"
        :label="t('CRM_KANBAN.BOOKING_AGENDA.DAY_LABEL')"
      />

      <div v-if="durationOptions.length > 1" class="flex flex-col gap-1.5">
        <span class="text-sm font-medium text-n-slate-12">
          {{ t('CRM_KANBAN.BOOKING_AGENDA.DURATION_LABEL') }}
        </span>
        <ChoiceSelect
          v-model="duration"
          :options="durationOptions"
          :aria-label="t('CRM_KANBAN.BOOKING_AGENDA.DURATION_LABEL')"
        />
      </div>

      <fieldset class="flex flex-col gap-2">
        <legend class="mb-1 text-sm font-medium text-n-slate-12">
          {{ t('CRM_KANBAN.BOOKING_AGENDA.TIME_LABEL') }}
        </legend>
        <p
          v-if="isLoadingSlots"
          role="status"
          class="mb-0 text-sm text-n-slate-11"
        >
          {{ t('CRM_KANBAN.BOOKING_AGENDA.SLOTS_LOADING') }}
        </p>
        <div
          v-else-if="slots.length"
          class="flex flex-wrap gap-2"
          data-booking-agenda-slots
        >
          <button
            v-for="slot in slots"
            :key="slot"
            type="button"
            :aria-pressed="startsAt === slot"
            class="min-h-11 min-w-[4.5rem] rounded-lg px-3 text-sm font-medium tabular-nums outline outline-1 transition-colors"
            :class="
              startsAt === slot
                ? 'bg-n-brand text-white outline-n-brand'
                : 'bg-n-alpha-1 text-n-slate-12 outline-n-weak hover:bg-n-alpha-2'
            "
            @click="startsAt = slot"
          >
            {{ timeLabel(slot) }}
          </button>
        </div>
        <div v-else class="flex flex-col items-start gap-2">
          <p class="mb-0 text-sm text-n-slate-11">
            {{ t('CRM_KANBAN.BOOKING_AGENDA.NO_SLOTS') }}
          </p>
          <NextButton
            v-if="nextSlot"
            type="button"
            outline
            slate
            class="min-h-11"
            :label="t('CRM_KANBAN.BOOKING_AGENDA.NEXT_SLOT')"
            data-booking-agenda-next
            @click="goToNextSlot"
          />
        </div>
        <p v-if="showErrors && !startsAt" class="mb-0 text-sm text-n-ruby-11">
          {{ t('CRM_KANBAN.BOOKING_AGENDA.PICK_TIME') }}
        </p>
        <p v-if="page?.timezone" class="mb-0 text-xs text-n-slate-11">
          {{
            t('CRM_KANBAN.BOOKING_AGENDA.TIMEZONE_HINT', {
              timezone: page.timezone,
            })
          }}
        </p>
      </fieldset>

      <div v-if="locationOptions.length > 1" class="flex flex-col gap-1.5">
        <span class="text-sm font-medium text-n-slate-12">
          {{ t('CRM_KANBAN.BOOKING_AGENDA.LOCATION_LABEL') }}
        </span>
        <ChoiceSelect
          v-model="location"
          :options="locationOptions"
          :aria-label="t('CRM_KANBAN.BOOKING_AGENDA.LOCATION_LABEL')"
        />
      </div>
      <p v-else-if="locationLabel" class="mb-0 text-sm text-n-slate-12">
        {{
          t('CRM_KANBAN.BOOKING_AGENDA.LOCATION_VALUE', {
            place: locationLabel,
          })
        }}
      </p>

      <label
        v-if="page?.notices"
        class="flex min-h-11 cursor-pointer items-center gap-3 rounded-lg bg-n-alpha-1 px-3 py-2"
      >
        <input
          v-model="notify"
          type="checkbox"
          class="size-5 flex-shrink-0 accent-n-brand"
          data-booking-agenda-notify
        />
        <span class="flex min-w-0 flex-col">
          <span class="text-sm font-medium text-n-slate-12">
            {{ t('CRM_KANBAN.BOOKING_AGENDA.NOTIFY') }}
          </span>
          <span class="text-xs text-n-slate-11">
            {{ t('CRM_KANBAN.BOOKING_AGENDA.NOTIFY_HINT') }}
          </span>
          <span class="text-xs text-n-slate-11" data-booking-agenda-notify-when>
            {{ t('CRM_KANBAN.BOOKING_AGENDA.NOTIFY_WHEN') }}
          </span>
        </span>
      </label>

      <NextButton
        type="button"
        link
        slate
        class="min-h-11 self-start"
        icon="i-lucide-link"
        :label="t('CRM_KANBAN.BOOKING_AGENDA.SEND_LINK')"
        :is-loading="isPreparingLink"
        data-booking-agenda-send-link
        @click="prepareLink"
      />
    </template>
  </div>
</template>
