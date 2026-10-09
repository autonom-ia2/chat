<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useFlow } from '../composables/useBookingFlow';
import { googleCalendarUrl } from '../helpers/calendar';
import { whenLabel } from '../helpers/datetime';
import { locationAddress } from '../helpers/locations';
import { safeAbsoluteUrl, safeUrl } from '../helpers/url';
import ActionButton from './ActionButton.vue';
import BrandHeader from './BrandHeader.vue';
import ManageError from './ManageError.vue';
import MeetingCard from './MeetingCard.vue';
import WhatsAppButton from './WhatsAppButton.vue';

// Tela da reunião pelo link do cliente (J5 "Sua conversa", contrato F2-A). Uma ação principal ("Vou estar lá");
// mudar e cancelar só dentro do prazo (`can_change`), senão a frase com o prazo e o WhatsApp da empresa. Reunião
// cancelada: "Cancelada", sem agenda nem "Entrar", com "Marcar outro horário" pela página (pausada: WhatsApp).
// "Parar avisos" some quando os avisos já pararam (RA-18, J5-A7).
const { page, invite, clientZone, manage } = useFlow();
const { t, locale } = useI18n();

const RESULT_TITLES = {
  confirmed: 'BOOKING_V2.MANAGE.TITLE_CONFIRMED',
  rescheduled: 'BOOKING_V2.MANAGE.TITLE_RESCHEDULED',
  stopped: 'BOOKING_V2.MANAGE.TITLE_STOPPED',
};
const BADGES = {
  confirmed: {
    key: 'BOOKING_V2.MANAGE.BADGE_CONFIRMED',
    classes: 'bg-green-50 text-green-900',
  },
  change_requested: {
    key: 'BOOKING_V2.MANAGE.BADGE_CHANGE_REQUESTED',
    classes: 'bg-yellow-100 text-yellow-900',
  },
};
const NOTIFIED_RESULTS = ['confirmed', 'rescheduled', 'canceled'];

const meeting = computed(() => manage.meeting.value);
const isCanceled = computed(() => manage.isCanceled.value);
const result = computed(() => manage.notice.value);
const agentName = computed(
  () => meeting.value.agent_name || page.value.agent_name || ''
);

const title = computed(() => {
  if (isCanceled.value) return t('BOOKING_V2.MANAGE.TITLE_CANCELED');
  const key = RESULT_TITLES[result.value] || 'BOOKING_V2.MANAGE.TITLE';
  return t(key);
});
const icon = computed(() => {
  if (isCanceled.value) return 'i-lucide-calendar-x';
  return result.value ? 'i-lucide-check' : 'i-lucide-calendar-check';
});
const badge = computed(() =>
  isCanceled.value ? null : BADGES[meeting.value.confirmation_status] || null
);
const notified = computed(() =>
  NOTIFIED_RESULTS.includes(result.value) && agentName.value
    ? t('BOOKING_V2.DONE.NOTIFIED', { name: agentName.value })
    : ''
);

const whatsappUrl = computed(() => manage.whatsappUrl.value);
const hasWhatsApp = computed(() => !!safeAbsoluteUrl(whatsappUrl.value));
const deadline = computed(() =>
  meeting.value.change_deadline
    ? whenLabel(meeting.value.change_deadline, locale.value, clientZone)
    : ''
);

const icsUrl = computed(() => safeUrl(meeting.value.ics_url));
const googleUrl = computed(() => {
  const location = meeting.value.location || {};
  return googleCalendarUrl({
    title: t('BOOKING_V2.DONE.CALENDAR_TITLE', {
      name: agentName.value || page.value.title || '',
    }),
    startsAt: meeting.value.starts_at,
    endsAt: meeting.value.ends_at,
    location:
      locationAddress(location) || safeAbsoluteUrl(location.join_url) || '',
  });
});
// Marcar de novo é uma reserva nova pela página (o convite já foi usado): só com a página aberta.
const bookAgainUrl = computed(() => {
  const slug = invite.invite.value?.page_slug;
  if (!slug || page.value.paused) return null;
  return safeUrl(`/book/${encodeURIComponent(slug)}`);
});
</script>

<template>
  <section class="flex flex-col gap-6" aria-labelledby="step-heading">
    <BrandHeader :page="page" />
    <div class="flex flex-col items-center gap-3 text-center">
      <span
        aria-hidden="true"
        class="flex size-14 items-center justify-center rounded-full text-2xl"
        :class="
          result && !isCanceled
            ? 'bg-[var(--brand)] font-bold text-white'
            : 'bg-slate-100 text-slate-600'
        "
      >
        <span :class="icon" />
      </span>
      <h1
        id="step-heading"
        data-step-heading
        tabindex="-1"
        class="text-2xl font-bold text-slate-900 focus:outline-none"
      >
        {{ title }}
      </h1>
      <p
        v-if="badge"
        data-testid="manage-badge"
        class="rounded-full px-4 py-1 text-base font-semibold"
        :class="badge.classes"
      >
        {{ t(badge.key) }}
      </p>
    </div>

    <ManageError />

    <MeetingCard :meeting="meeting" :show-join="!isCanceled" />
    <p v-if="notified" class="text-center text-base text-slate-700">
      {{ notified }}
    </p>

    <div v-if="isCanceled" class="flex flex-col gap-3">
      <p class="text-base text-slate-800">
        {{
          bookAgainUrl
            ? t('BOOKING_V2.MANAGE.CANCELED_BODY')
            : t('BOOKING_V2.MANAGE.CANCELED_BODY_CLOSED')
        }}
      </p>
      <ActionButton v-if="bookAgainUrl" :href="bookAgainUrl">
        {{ t('BOOKING_V2.MANAGE.BOOK_AGAIN') }}
      </ActionButton>
      <WhatsAppButton
        :url="whatsappUrl"
        :variant="bookAgainUrl ? 'secondary' : 'primary'"
      />
    </div>

    <div v-else class="flex flex-col gap-3">
      <ActionButton
        v-if="manage.canConfirm.value"
        :disabled="manage.isWorking.value"
        @click="manage.confirm"
      >
        {{ t('BOOKING_V2.MANAGE.CONFIRM') }}
      </ActionButton>
      <ActionButton
        v-if="manage.canReschedule.value"
        variant="secondary"
        @click="manage.startReschedule"
      >
        {{ t('BOOKING_V2.MANAGE.RESCHEDULE') }}
      </ActionButton>
      <ActionButton v-if="icsUrl" :href="icsUrl" variant="secondary" download>
        {{ t('BOOKING_V2.DONE.SAVE') }}
      </ActionButton>
      <ActionButton
        v-if="googleUrl"
        :href="googleUrl"
        variant="secondary"
        external
      >
        {{ t('BOOKING_V2.DONE.GOOGLE') }}
      </ActionButton>
      <ActionButton
        v-if="manage.canChange.value"
        variant="ghost"
        @click="manage.openCancel"
      >
        {{ t('BOOKING_V2.MANAGE.CANCEL') }}
      </ActionButton>
      <div
        v-else
        data-testid="manage-locked"
        class="flex flex-col gap-3 rounded-2xl border-2 border-slate-200 p-4"
      >
        <p class="text-base text-slate-800">
          {{
            deadline
              ? t('BOOKING_V2.MANAGE.LOCKED', { deadline })
              : t('BOOKING_V2.MANAGE.LOCKED_NO_DEADLINE')
          }}
          {{ hasWhatsApp ? t('BOOKING_V2.MANAGE.LOCKED_WHATSAPP') : '' }}
        </p>
        <WhatsAppButton :url="whatsappUrl" />
      </div>
    </div>

    <p
      v-if="meeting.notices_stopped"
      data-testid="notices-stopped"
      class="text-center text-base text-slate-700"
    >
      {{ t('BOOKING_V2.MANAGE.STOPPED') }}
    </p>
    <ActionButton v-else variant="ghost" @click="manage.openStop">
      {{ t('BOOKING_V2.MANAGE.STOP') }}
    </ActionButton>
  </section>
</template>
