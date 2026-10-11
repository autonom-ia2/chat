<script setup>
import { computed, onBeforeUnmount, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import Button from 'dashboard/components-next/button/Button.vue';
import { useEmitter } from 'dashboard/composables/emitter';
import { useCrmFollowUpReminders } from 'dashboard/composables/useCrmFollowUpReminders';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import { emitter } from 'shared/helpers/mitt';
import { frontendURL } from 'dashboard/helper/URLHelper';
import { bookingAlert } from 'dashboard/routes/dashboard/crm/helpers/bookingAlert';
import { formatBookingTime } from 'dashboard/routes/dashboard/crm/helpers/meetingNotices';

const { t, locale } = useI18n();
const router = useRouter();
const isSaving = ref(false);

const {
  activeReminder,
  hasReminder,
  enqueueReminder,
  fetchMissedReminders,
  completeReminder,
  dismissReminder,
  isCrmEnabled,
} = useCrmFollowUpReminders();

const title = computed(
  () => activeReminder.value?.title || t('CRM_KANBAN.FOLLOW_UP_REMINDER.TITLE')
);
const cardTitle = computed(() => activeReminder.value?.card?.title || '');
const dueLabel = computed(() => {
  const dueAt = activeReminder.value?.due_at;
  if (!dueAt) return '';
  return new Date(dueAt).toLocaleString(locale.value.replace('_', '-'));
});
const modeLabel = computed(() => {
  if (activeReminder.value?.automation_mode === 'snooze_conversation') {
    return t('CRM_KANBAN.FOLLOW_UP_REMINDER.MODE_SNOOZE');
  }
  return t('CRM_KANBAN.FOLLOW_UP_REMINDER.MODE_REMINDER');
});

// Alerta do agendamento (#1291): chega pelo caminho dos lembretes, mas não é um
// retorno atrasado. Ganha título, frase inteira e ações próprias; sem "Venceu em".
const NOTICE_REASONS =
  'CRM_KANBAN.CALENDAR.MEETING_DETAIL.NOTICES.SKIP_REASONS';
const alert = computed(() => bookingAlert(activeReminder.value));
const heading = computed(() => {
  if (!alert.value) return t('CRM_KANBAN.FOLLOW_UP_REMINDER.HEADING');
  return t(
    alert.value.isNoticeFailed
      ? 'CRM_KANBAN.FOLLOW_UP_REMINDER.BOOKING_ALERT.NOTICE_FAILED_HEADING'
      : 'CRM_KANBAN.FOLLOW_UP_REMINDER.BOOKING_ALERT.HEADING'
  );
});
const alertText = computed(() => {
  const { isNoticeFailed, name, startsAt, reasonKey } = alert.value || {};
  const when = formatBookingTime(startsAt, locale.value);
  // Alerta gravado antes do #1291 não traz cliente nem horário: vale o texto do backend.
  if (!isNoticeFailed || !name || !when) return title.value;
  if (!reasonKey)
    return t('CRM_KANBAN.FOLLOW_UP_REMINDER.BOOKING_ALERT.NOTICE_FAILED_BODY', {
      name,
      when,
    });
  return t(
    'CRM_KANBAN.FOLLOW_UP_REMINDER.BOOKING_ALERT.NOTICE_FAILED_BODY_REASON',
    {
      name,
      when,
      reason: t(`${NOTICE_REASONS}.${reasonKey}`),
    }
  );
});

const openCrm = async () => {
  const accountId = activeReminder.value?.account_id;
  if (!accountId) return;
  await router.push(frontendURL(`accounts/${accountId}/crm`));
};

// Abre o card do alerta: é nele que ficam a conversa do cliente e os avisos da reunião.
// Com o quadro desta conta já na tela, pede a abertura ao próprio quadro: repetir a
// mesma URL não reabriria um card que já foi aberto por ela.
const openCard = async () => {
  const { account_id: accountId, card_id: cardId, id } = activeReminder.value;
  if (!accountId || !cardId) return;
  const { name, params } = router.currentRoute.value;
  const isOnBoard =
    name === 'crm_kanban_index' &&
    String(params.accountId) === String(accountId);
  if (isOnBoard) {
    emitter.emit(BUS_EVENTS.CRM_OPEN_CARD, cardId);
  } else {
    await router.push({
      path: frontendURL(`accounts/${accountId}/crm`),
      query: { card_id: String(cardId) },
    });
  }
  await dismissReminder(id, accountId);
};

const runAction = async action => {
  if (!activeReminder.value?.id || isSaving.value) return;
  isSaving.value = true;
  try {
    if (action === 'complete') {
      await completeReminder(
        activeReminder.value.id,
        activeReminder.value.account_id
      );
    } else {
      await dismissReminder(
        activeReminder.value.id,
        activeReminder.value.account_id
      );
    }
  } finally {
    isSaving.value = false;
  }
};

const REMINDER_POLL_MS = 60_000;
let reminderPollTimer = null;

useEmitter(BUS_EVENTS.CRM_FOLLOW_UP_DUE, enqueueReminder);
useEmitter(BUS_EVENTS.WEBSOCKET_RECONNECT_COMPLETED, () => {
  if (isCrmEnabled()) fetchMissedReminders();
});

onMounted(() => {
  if (!isCrmEnabled()) return;

  fetchMissedReminders();
  reminderPollTimer = window.setInterval(
    fetchMissedReminders,
    REMINDER_POLL_MS
  );
});

onBeforeUnmount(() => {
  if (reminderPollTimer) window.clearInterval(reminderPollTimer);
});
</script>

<template>
  <transition
    enter-active-class="transition duration-200 ease-out"
    enter-from-class="translate-y-4 opacity-0"
    leave-active-class="transition duration-150 ease-in"
    leave-to-class="translate-y-2 opacity-0"
  >
    <aside
      v-if="hasReminder"
      class="fixed bottom-6 z-[70] w-[24rem] max-w-[calc(100vw-2rem)] rounded-xl border border-n-brand/30 bg-n-surface-2 p-4 shadow-xl ltr:right-6 rtl:left-6"
      role="alertdialog"
      :aria-label="alert ? heading : title"
    >
      <div class="mb-3 flex items-start gap-3">
        <span
          class="mt-0.5 flex h-9 w-9 shrink-0 items-center justify-center rounded-full"
          :class="
            alert?.isNoticeFailed
              ? 'bg-n-amber-9/10 text-n-amber-11'
              : 'bg-n-brand/15 text-n-brand'
          "
        >
          <span
            class="text-lg"
            :class="
              alert?.isNoticeFailed
                ? 'i-lucide-triangle-alert'
                : 'i-lucide-bell-ring'
            "
          />
        </span>
        <div class="min-w-0">
          <p class="mb-1 text-sm font-medium text-n-slate-12">
            {{ heading }}
          </p>
          <template v-if="alert">
            <p
              class="mb-1 break-words text-sm text-n-slate-12"
              data-test-id="booking-alert-text"
            >
              {{ alertText }}
            </p>
            <p v-if="alert.isNoticeFailed" class="mb-1 text-xs text-n-slate-11">
              {{
                t(
                  'CRM_KANBAN.FOLLOW_UP_REMINDER.BOOKING_ALERT.NOTICE_FAILED_HINT'
                )
              }}
            </p>
          </template>
          <p v-else class="mb-0 truncate text-sm text-n-slate-12">
            {{ title }}
          </p>
          <p v-if="cardTitle" class="mb-0 truncate text-xs text-n-slate-11">
            {{ t('CRM_KANBAN.FOLLOW_UP_REMINDER.CARD', { card: cardTitle }) }}
          </p>
          <template v-if="!alert">
            <p v-if="dueLabel" class="mb-0 text-xs text-n-slate-10">
              {{ t('CRM_KANBAN.FOLLOW_UP_REMINDER.DUE', { due: dueLabel }) }}
            </p>
            <p class="mb-0 text-[11px] text-n-slate-10">{{ modeLabel }}</p>
          </template>
        </div>
      </div>

      <p
        v-if="activeReminder?.description"
        class="mb-3 max-h-48 overflow-y-auto whitespace-pre-wrap break-words text-xs leading-5 text-n-slate-11"
      >
        {{ activeReminder.description }}
      </p>
      <div v-if="alert" class="flex flex-wrap items-center justify-end gap-2">
        <Button
          :label="t('CRM_KANBAN.FOLLOW_UP_REMINDER.BOOKING_ALERT.ACK')"
          slate
          ghost
          sm
          :is-loading="isSaving"
          @click="runAction('complete')"
        />
        <Button
          :label="t('CRM_KANBAN.FOLLOW_UP_REMINDER.BOOKING_ALERT.OPEN_CARD')"
          icon="i-lucide-arrow-right"
          sm
          @click="openCard"
        />
      </div>
      <div v-else class="flex flex-wrap items-center justify-end gap-2">
        <Button
          :label="t('CRM_KANBAN.FOLLOW_UP_REMINDER.OPEN_CRM')"
          slate
          faded
          sm
          @click="openCrm"
        />
        <Button
          :label="t('CRM_KANBAN.FOLLOW_UP_REMINDER.DISMISS')"
          slate
          ghost
          sm
          :is-loading="isSaving"
          @click="runAction('dismiss')"
        />
        <Button
          :label="t('CRM_KANBAN.FOLLOW_UP_REMINDER.COMPLETE')"
          icon="i-lucide-check"
          sm
          :is-loading="isSaving"
          @click="runAction('complete')"
        />
      </div>
    </aside>
  </transition>
</template>
