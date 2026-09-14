<script setup>
import { computed, onBeforeUnmount, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import Button from 'dashboard/components-next/button/Button.vue';
import { useEmitter } from 'dashboard/composables/emitter';
import { useCrmFollowUpReminders } from 'dashboard/composables/useCrmFollowUpReminders';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import { frontendURL } from 'dashboard/helper/URLHelper';

const { t } = useI18n();
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
  return new Date(dueAt).toLocaleString();
});
const modeLabel = computed(() => {
  if (activeReminder.value?.automation_mode === 'snooze_conversation') {
    return t('CRM_KANBAN.FOLLOW_UP_REMINDER.MODE_SNOOZE');
  }
  return t('CRM_KANBAN.FOLLOW_UP_REMINDER.MODE_REMINDER');
});

const openCrm = async () => {
  const accountId = activeReminder.value?.account_id;
  if (!accountId) return;
  await router.push(frontendURL(`accounts/${accountId}/crm`));
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
      :aria-label="title"
    >
      <div class="mb-3 flex items-start gap-3">
        <span
          class="mt-0.5 flex h-9 w-9 shrink-0 items-center justify-center rounded-full bg-n-brand/15 text-n-brand"
        >
          <span class="i-lucide-bell-ring text-lg" />
        </span>
        <div class="min-w-0">
          <p class="mb-1 text-sm font-medium text-n-slate-12">
            {{ t('CRM_KANBAN.FOLLOW_UP_REMINDER.HEADING') }}
          </p>
          <p class="mb-0 truncate text-sm text-n-slate-12">{{ title }}</p>
          <p v-if="cardTitle" class="mb-0 truncate text-xs text-n-slate-11">
            {{ t('CRM_KANBAN.FOLLOW_UP_REMINDER.CARD', { card: cardTitle }) }}
          </p>
          <p v-if="dueLabel" class="mb-0 text-xs text-n-slate-10">
            {{ t('CRM_KANBAN.FOLLOW_UP_REMINDER.DUE', { due: dueLabel }) }}
          </p>
          <p class="mb-0 text-[11px] text-n-slate-10">{{ modeLabel }}</p>
        </div>
      </div>

      <p
        v-if="activeReminder?.description"
        class="mb-3 max-h-48 overflow-y-auto whitespace-pre-wrap break-words text-xs leading-5 text-n-slate-11"
      >
        {{ activeReminder.description }}
      </p>
      <div class="flex flex-wrap items-center justify-end gap-2">
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
