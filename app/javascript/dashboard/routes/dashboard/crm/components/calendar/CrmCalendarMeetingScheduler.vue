<script setup>
import { computed, nextTick, ref, watch } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';

import crmBookingPagesAPI from 'dashboard/api/crmBookingPages';
import { getUserPermissions } from 'dashboard/helper/permissionsHelper';
import {
  canSeeBookingSettings,
  isBookingV2Available,
} from 'dashboard/routes/dashboard/settings/booking/bookingAccess';
import CrmBookingAgendaForm from './CrmBookingAgendaForm.vue';
import CrmProviderMeetingForm from './CrmProviderMeetingForm.vue';
import { toDateInput } from './meetingDates';
import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';

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
  // Card completo (contato, conversa): a marcação pela agenda (#1265) usa.
  card: { type: Object, default: null },
});

const emit = defineEmits(['create', 'updated', 'close', 'update:show']);

// Reschedule mode reuses this scheduler when an existing meeting is passed in:
// it prefills every field and, on submit, only PATCHes start/end/timezone.
const isReschedule = computed(() => !!props.meeting?.id);

const route = useRoute();
const { t } = useI18n();

const dialogRef = ref(null);
const providerRef = ref(null);
const isScheduling = ref(false);

const currentAccountId = computed(
  () => props.accountId || route.params.accountId
);

const calendarInboxes = computed(() =>
  (props.availableInboxes || []).filter(
    inbox => inbox.calendar_enabled || inbox.calendarEnabled
  )
);

// This account has no calendar-enabled mailbox connected — show an empty state
// guiding the user to connect one instead of an empty mailbox picker.
const hasCalendarInbox = computed(() => calendarInboxes.value.length > 0);

// Marcar pela agenda (#1265): com o agendamento novo ligado na conta, a janela
// marca por uma página publicada, sem caixa Google/Microsoft. Com as duas, a
// pessoa escolhe a aba; o caminho do Google/Microsoft segue igual. Remarcar
// continua só pelo caminho antigo.
const MODE_AGENDA = 'agenda';
const MODE_PROVIDER = 'provider';
const BOOKING_SETTINGS_ROUTE = 'settings_booking';
const store = useStore();
const router = useRouter();
const agendaRef = ref(null);
const bookingPages = ref([]);
const isLoadingPages = ref(false);
const isAgendaSaving = ref(false);
const hasPagesError = ref(false);
let pagesRequest = 0;
const mode = ref(MODE_PROVIDER);

const isBookingV2 = computed(
  () =>
    !isReschedule.value &&
    isBookingV2Available(
      store.getters['accounts/getAccount']?.(currentAccountId.value)
    )
);
const hasAgenda = computed(
  () => isBookingV2.value && bookingPages.value.length > 0
);
const showModeTabs = computed(() => hasAgenda.value && hasCalendarInbox.value);
const isAgendaMode = computed(
  () => hasAgenda.value && mode.value === MODE_AGENDA
);
const showProviderForm = computed(
  () => hasCalendarInbox.value && !isAgendaMode.value
);
const showCreatePageEmpty = computed(
  () =>
    isBookingV2.value &&
    !isLoadingPages.value &&
    !hasPagesError.value &&
    !hasAgenda.value
);
const canOpenBookingSettings = computed(
  () =>
    canSeeBookingSettings({
      isAdministrator: store.getters.getCurrentRole === 'administrator',
      permissions: getUserPermissions(
        store.getters.getCurrentUser,
        currentAccountId.value
      ),
    }) && router.hasRoute(BOOKING_SETTINGS_ROUTE)
);
const showSaveButton = computed(() =>
  isAgendaMode.value
    ? !agendaRef.value?.isShowingLink
    : hasCalendarInbox.value && !isLoadingPages.value
);

// Sem acesso (401) ou flag desligada no servidor (404): a janela fica como
// era, só com o Google/Microsoft. Outra falha (rede, 500) mostra o erro com
// "Tentar de novo", nunca o "Crie sua página" para quem já tem página.
const HTTP_UNAUTHORIZED = 401;
const HTTP_NOT_FOUND = 404;
const loadBookingPages = async () => {
  pagesRequest += 1;
  const current = pagesRequest;
  bookingPages.value = [];
  hasPagesError.value = false;
  mode.value = MODE_PROVIDER;
  if (!isBookingV2.value) {
    isLoadingPages.value = false;
    return;
  }

  isLoadingPages.value = true;
  try {
    const { data } = await crmBookingPagesAPI.bookable();
    if (current !== pagesRequest) return;
    bookingPages.value = data?.payload || [];
    if (bookingPages.value.length) mode.value = MODE_AGENDA;
  } catch (exception) {
    if (current !== pagesRequest) return;
    const status = exception?.response?.status;
    hasPagesError.value = ![HTTP_UNAUTHORIZED, HTTP_NOT_FOUND].includes(status);
  } finally {
    if (current === pagesRequest) isLoadingPages.value = false;
  }
};

const openBookingSettings = () => {
  emit('update:show', false);
  emit('close');
  router.push({
    name: BOOKING_SETTINGS_ROUTE,
    params: { accountId: currentAccountId.value },
  });
};

const onAgendaBooked = meeting => {
  emit('create', meeting);
  emit('update:show', false);
  emit('close');
};

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

const onSchedule = () => {
  if (isAgendaMode.value) agendaRef.value?.submit();
  else providerRef.value?.submit();
};

const finish = () => {
  emit('update:show', false);
  emit('close');
};
const onProviderCreated = meeting => {
  emit('create', meeting);
  finish();
};
const onProviderUpdated = meeting => {
  emit('updated', meeting);
  finish();
};

const onClose = () => {
  if (isScheduling.value || isAgendaSaving.value) return;
  finish();
};

watch(
  () => props.show,
  isOpen => {
    if (isOpen) {
      nextTick(() => dialogRef.value?.open());
      loadBookingPages();
    } else {
      dialogRef.value?.close();
    }
  }
);
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

      <p
        v-if="isLoadingPages"
        role="status"
        class="mb-0 py-6 text-center text-sm text-n-slate-11"
      >
        {{ t('CRM_KANBAN.BOOKING_AGENDA.LOADING') }}
      </p>
      <div
        v-if="showModeTabs && !isLoadingPages"
        role="group"
        :aria-label="t('CRM_KANBAN.BOOKING_AGENDA.TABS_LABEL')"
        class="grid grid-cols-2 gap-1 rounded-lg bg-n-alpha-1 p-1"
        data-scheduler-tabs
      >
        <button
          v-for="tab in [MODE_AGENDA, MODE_PROVIDER]"
          :key="tab"
          type="button"
          :aria-pressed="mode === tab"
          class="min-h-11 rounded-md px-2 text-sm font-medium transition-colors"
          :class="
            mode === tab
              ? 'bg-n-solid-1 text-n-slate-12 shadow-sm'
              : 'text-n-slate-11 hover:text-n-slate-12'
          "
          :data-scheduler-tab="tab"
          :disabled="isScheduling || isAgendaSaving"
          @click="mode = tab"
        >
          {{
            tab === MODE_AGENDA
              ? t('CRM_KANBAN.BOOKING_AGENDA.TAB_AGENDA')
              : t('CRM_KANBAN.BOOKING_AGENDA.TAB_PROVIDER')
          }}
        </button>
      </div>

      <div
        v-if="hasPagesError && !isLoadingPages && !hasCalendarInbox"
        role="alert"
        class="flex flex-col items-center gap-3 rounded-lg bg-n-ruby-3 px-4 py-6 text-center text-sm text-n-ruby-11"
        data-booking-agenda-load-error
      >
        <span>{{ t('CRM_KANBAN.BOOKING_AGENDA.ERRORS.LOAD') }}</span>
        <Button
          type="button"
          outline
          slate
          class="min-h-11"
          :label="t('CRM_KANBAN.BOOKING_AGENDA.RETRY')"
          @click="loadBookingPages"
        />
      </div>

      <CrmBookingAgendaForm
        v-else-if="isAgendaMode && !isLoadingPages"
        ref="agendaRef"
        :pages="bookingPages"
        :card-id="cardId"
        :card="card"
        :initial-day="toDateInput(date)"
        @saving="isAgendaSaving = $event"
        @booked="onAgendaBooked"
      />

      <div
        v-else-if="showCreatePageEmpty && !hasCalendarInbox"
        class="flex flex-col items-center gap-3 rounded-lg bg-n-alpha-1 px-4 py-8 text-center outline outline-1 outline-n-weak"
        data-booking-agenda-empty
      >
        <span
          class="i-lucide-calendar-plus size-8 text-n-slate-10"
          aria-hidden="true"
        />
        <p class="mb-0 text-base font-medium text-n-slate-12">
          {{ t('CRM_KANBAN.BOOKING_AGENDA.EMPTY.TITLE') }}
        </p>
        <p class="mb-0 max-w-xs text-sm text-n-slate-11">
          {{
            canOpenBookingSettings
              ? t('CRM_KANBAN.BOOKING_AGENDA.EMPTY.DESC')
              : t('CRM_KANBAN.BOOKING_AGENDA.EMPTY.AGENT')
          }}
        </p>
        <Button
          v-if="canOpenBookingSettings"
          type="button"
          lg
          icon="i-lucide-calendar-plus"
          :label="t('CRM_KANBAN.BOOKING_AGENDA.EMPTY.OPEN')"
          data-booking-agenda-open-settings
          @click="openBookingSettings"
        />
      </div>

      <div
        v-else-if="!hasCalendarInbox && !isLoadingPages"
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

      <!-- Fica montado ao trocar de aba: o que foi digitado não se perde e o
      envio em andamento termina com o aviso de sempre. -->
      <CrmProviderMeetingForm
        v-if="hasCalendarInbox && !isLoadingPages"
        v-show="!isAgendaMode"
        ref="providerRef"
        :active="show"
        :account-id="currentAccountId"
        :card-id="cardId"
        :date="date"
        :available-inboxes="availableInboxes"
        :card-contact-email="cardContactEmail"
        :card-contact-name="cardContactName"
        :meeting="meeting"
        @saving="isScheduling = $event"
        @create="onProviderCreated"
        @updated="onProviderUpdated"
      />
    </div>

    <template #footer>
      <div
        class="flex w-full flex-col gap-3 md:flex-row md:items-center md:justify-between"
      >
        <span v-if="!showProviderForm || isLoadingPages" />
        <p
          v-else
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
            :disabled="isScheduling || isAgendaSaving"
            @click="onClose"
          />
          <Button
            v-if="isAgendaMode && showSaveButton"
            type="submit"
            variant="solid"
            color="blue"
            size="sm"
            class="min-h-11"
            icon="i-lucide-calendar-check"
            :label="
              isAgendaSaving
                ? t('CRM_KANBAN.BOOKING_AGENDA.SAVING')
                : t('CRM_KANBAN.BOOKING_AGENDA.SAVE')
            "
            :is-loading="isAgendaSaving"
            :disabled="isAgendaSaving"
            data-booking-agenda-save
          />
          <Button
            v-else-if="!isAgendaMode && showSaveButton"
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
