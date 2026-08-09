<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import CrmKanbanAPI from 'dashboard/api/crmKanban';

const props = defineProps({
  card: { type: Object, default: null },
});

const emit = defineEmits(['reset']);

const { t } = useI18n();

const isResetting = ref(false);
const reactivateDialogRef = ref(null);

const cardId = computed(() => props.card?.id || null);
const state = computed(
  () =>
    props.card?.auto_followup ||
    props.card?.metadata?.ai?.auto_followup_state ||
    null
);
const hasState = computed(
  () => Boolean(state.value) && Object.keys(state.value).length > 0
);

const touches = computed(() =>
  Array.isArray(state.value?.touches) ? state.value.touches : []
);
const maxTouches = computed(() => {
  const max = Number(state.value?.max_touches);
  return Number.isFinite(max) && max > 0 ? max : touches.value.length || 1;
});
const usedTouches = computed(() => {
  const sent = touches.value.filter(item => item?.outcome === 'sent').length;
  return sent || touches.value.length;
});
const isSpent = computed(() => state.value?.spent === true);
const stoppedReason = computed(() => state.value?.stopped_reason || null);
const isOptedOut = computed(() => stoppedReason.value === 'opt_out');

const statusText = computed(() => {
  if (!hasState.value)
    return t('CRM_KANBAN.DRAWER.AUTO_FOLLOWUP.STATUS_NOT_STARTED');
  const reason = stoppedReason.value;
  if (reason === 'opt_out')
    return t('CRM_KANBAN.DRAWER.AUTO_FOLLOWUP.STATUS_OPT_OUT');
  if (reason === 'replied')
    return t('CRM_KANBAN.DRAWER.AUTO_FOLLOWUP.STATUS_REPLIED');
  if (reason === 'conversation_closed')
    return t('CRM_KANBAN.DRAWER.AUTO_FOLLOWUP.STATUS_CLOSED');
  if (reason === 'no_open_loop')
    return t('CRM_KANBAN.DRAWER.AUTO_FOLLOWUP.STATUS_NO_LOOP');
  if (reason === 'no_template')
    return t('CRM_KANBAN.DRAWER.AUTO_FOLLOWUP.STATUS_NO_TEMPLATE');
  if (reason === 'send_failed')
    return t('CRM_KANBAN.DRAWER.AUTO_FOLLOWUP.STATUS_FAILED');
  if (isSpent.value && reason === 'max_touches')
    return t('CRM_KANBAN.DRAWER.AUTO_FOLLOWUP.STATUS_DONE', {
      total: maxTouches.value,
    });
  return t('CRM_KANBAN.DRAWER.AUTO_FOLLOWUP.STATUS_ACTIVE', {
    n: usedTouches.value,
    total: maxTouches.value,
  });
});

const timelineEntries = computed(() =>
  touches.value.map((item, index) => {
    const n = item?.touch || index + 1;
    if (item?.outcome === 'sent' && item?.mode === 'template') {
      return {
        key: index,
        label: t('CRM_KANBAN.DRAWER.AUTO_FOLLOWUP.TIMELINE_TOUCH_TEMPLATE', {
          n,
          name: item?.template_name || '',
        }),
        icon: 'i-lucide-file-text',
        tone: 'text-n-amber-11',
      };
    }
    if (item?.outcome === 'sent') {
      return {
        key: index,
        label: t('CRM_KANBAN.DRAWER.AUTO_FOLLOWUP.TIMELINE_TOUCH_FREE', { n }),
        icon: 'i-lucide-sparkles',
        tone: 'text-n-teal-11',
      };
    }
    return {
      key: index,
      label: t('CRM_KANBAN.DRAWER.AUTO_FOLLOWUP.TIMELINE_TOUCH_SKIPPED', { n }),
      icon: 'i-lucide-circle-slash',
      tone: 'text-n-slate-10',
    };
  })
);

const resetButtonLabel = computed(() =>
  isOptedOut.value
    ? t('CRM_KANBAN.DRAWER.AUTO_FOLLOWUP.REACTIVATE')
    : t('CRM_KANBAN.DRAWER.AUTO_FOLLOWUP.RESET')
);

const resetCycle = async () => {
  if (!cardId.value || isResetting.value) return;
  isResetting.value = true;
  try {
    await CrmKanbanAPI.resetAutoFollowup(cardId.value);
    useAlert(t('CRM_KANBAN.DRAWER.AUTO_FOLLOWUP.RESET_SUCCESS'));
    reactivateDialogRef.value?.close();
    emit('reset');
  } catch {
    useAlert(t('CRM_KANBAN.DRAWER.AUTO_FOLLOWUP.RESET_ERROR'));
  } finally {
    isResetting.value = false;
  }
};

const onResetClick = () => {
  if (isOptedOut.value) {
    reactivateDialogRef.value?.open();
    return;
  }
  resetCycle();
};
</script>

<template>
  <div class="grid gap-3 rounded-lg border border-n-weak bg-n-alpha-black2 p-4">
    <div class="flex items-start justify-between gap-3">
      <div class="flex items-center gap-2">
        <span class="i-lucide-bot size-4 text-n-slate-11" />
        <p class="mb-0 text-sm font-medium text-n-slate-12">
          {{ t('CRM_KANBAN.DRAWER.AUTO_FOLLOWUP.TITLE') }}
        </p>
      </div>
      <span
        class="shrink-0 text-xs font-medium"
        :class="
          isOptedOut
            ? 'rounded-full bg-n-amber-3 px-2 py-0.5 text-n-amber-11'
            : 'text-n-slate-11'
        "
      >
        {{ statusText }}
      </span>
    </div>

    <ul v-if="timelineEntries.length" class="grid gap-1.5">
      <li
        v-for="entry in timelineEntries"
        :key="entry.key"
        class="flex items-center gap-2 text-xs text-n-slate-11"
      >
        <span class="size-3.5 shrink-0" :class="[entry.icon, entry.tone]" />
        <span class="min-w-0 truncate">{{ entry.label }}</span>
      </li>
    </ul>

    <p
      v-if="isOptedOut"
      class="mb-0 flex items-center gap-1.5 text-xs text-n-slate-11"
    >
      <span class="i-lucide-hand size-3.5 shrink-0" />
      <span>{{ t('CRM_KANBAN.DRAWER.AUTO_FOLLOWUP.OPT_OUT_HINT') }}</span>
    </p>

    <div v-if="isSpent || isOptedOut" class="flex justify-end">
      <Button
        :label="resetButtonLabel"
        icon="i-lucide-rotate-ccw"
        slate
        faded
        sm
        :is-loading="isResetting"
        @click="onResetClick"
      />
    </div>

    <Dialog
      ref="reactivateDialogRef"
      type="alert"
      :title="t('CRM_KANBAN.DRAWER.AUTO_FOLLOWUP.REACTIVATE_CONFIRM_TITLE')"
      :description="
        t('CRM_KANBAN.DRAWER.AUTO_FOLLOWUP.REACTIVATE_CONFIRM_BODY')
      "
      :confirm-button-label="
        t('CRM_KANBAN.DRAWER.AUTO_FOLLOWUP.REACTIVATE_CONFIRM_OK')
      "
      :is-loading="isResetting"
      :disable-confirm-button="isResetting"
      @confirm="resetCycle"
    />
  </div>
</template>
