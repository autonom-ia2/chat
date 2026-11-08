<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';
import CrmKanbanAPI from 'dashboard/api/crmKanban';
import ContactAPI from 'dashboard/api/contacts';
import { textosCom } from './card/textos';

const props = defineProps({
  card: { type: Object, default: null },
  canManageAi: { type: Boolean, default: false },
  canManageRecords: { type: Boolean, default: false },
  // #1423 — prefixo com as frases da gaveta nova; vazio = textos de sempre.
  textos: { type: String, default: '' },
});

const emit = defineEmits(['reset']);

// Mesma chave de Crm::Ai::Config::CONTACT_FOLLOWUP_DISABLED_KEY (exclusão por contato).
const CONTACT_FOLLOWUP_DISABLED_KEY = 'crm_ai_followup_disabled';

const { t, te } = useI18n();
const label = textosCom(
  { t, te },
  props.textos,
  'CRM_KANBAN.DRAWER.AUTO_FOLLOWUP'
);

const isResetting = ref(false);
const isSavingContact = ref(false);
const reactivateDialogRef = ref(null);
const detailsOpen = ref(false);

const cardId = computed(() => props.card?.id || null);
watch(cardId, () => {
  detailsOpen.value = false;
});
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
  const sent = touches.value.filter(item =>
    ['sent', 'reminded'].includes(item?.outcome)
  ).length;
  return sent || touches.value.length;
});
const isSpent = computed(() => state.value?.spent === true);
const stoppedReason = computed(() => state.value?.stopped_reason || null);
const isOptedOut = computed(() => stoppedReason.value === 'opt_out');
const contact = computed(() => props.card?.contact || null);
const isContactDisabled = computed(
  () =>
    contact.value?.additional_attributes?.[CONTACT_FOLLOWUP_DISABLED_KEY] ===
    true
);

const statusText = computed(() => {
  if (isContactDisabled.value) return label('STATUS_CONTACT_DISABLED');
  if (!hasState.value) return label('STATUS_NOT_STARTED');
  const reason = stoppedReason.value;
  // Parou porque o contato saiu do follow-up de IA, inclusive por "Este contato é" (#2084).
  if (reason === 'contact_disabled') return label('STATUS_CONTACT_DISABLED');
  if (reason === 'opt_out') return label('STATUS_OPT_OUT');
  if (reason === 'replied') return label('STATUS_REPLIED');
  if (reason === 'conversation_closed') return label('STATUS_CLOSED');
  if (reason === 'no_open_loop') return label('STATUS_NO_LOOP');
  if (reason === 'no_template') return label('STATUS_NO_TEMPLATE');
  if (reason === 'send_failed') return label('STATUS_FAILED');
  if (isSpent.value && reason === 'max_touches')
    return label('STATUS_DONE', {
      total: maxTouches.value,
    });
  return label('STATUS_ACTIVE', {
    n: usedTouches.value,
    total: maxTouches.value,
  });
});

const timelineEntries = computed(() =>
  touches.value.map((item, index) => {
    const n = item?.touch || index + 1;
    if (item?.outcome === 'reminded') {
      return {
        key: index,
        label: label('TIMELINE_TOUCH_REMINDER', {
          n,
        }),
        icon: 'i-lucide-bell-ring',
        tone: 'text-n-teal-11',
      };
    }
    if (item?.outcome === 'sent' && item?.mode === 'template') {
      return {
        key: index,
        label: label('TIMELINE_TOUCH_TEMPLATE', {
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
        label: label('TIMELINE_TOUCH_FREE', { n }),
        icon: 'i-lucide-sparkles',
        tone: 'text-n-teal-11',
      };
    }
    return {
      key: index,
      label: label('TIMELINE_TOUCH_SKIPPED', { n }),
      icon: 'i-lucide-circle-slash',
      tone: 'text-n-slate-10',
    };
  })
);

const resetButtonLabel = computed(() =>
  isOptedOut.value ? label('REACTIVATE') : label('RESET')
);

// chat#1325: quando a recusa do contato continua depois do reset, o aviso diz por quê.
const resetResultMessage = result => {
  if (result === 'kept_other_cards') {
    return label('RESET_KEPT_OTHER_CARDS');
  }
  if (result === 'kept_no_permission') {
    return label('RESET_KEPT_NO_PERMISSION');
  }
  if (result === 'kept_other_source') {
    return label('RESET_KEPT_OTHER_SOURCE');
  }
  return label('RESET_SUCCESS');
};

const resetCycle = async () => {
  if (!props.canManageAi || !cardId.value || isResetting.value) return;
  isResetting.value = true;
  try {
    const response = await CrmKanbanAPI.resetAutoFollowup(cardId.value);
    useAlert(resetResultMessage(response?.data?.contact_opt_out));
    reactivateDialogRef.value?.close();
    emit('reset');
  } catch {
    useAlert(label('RESET_ERROR'));
  } finally {
    isResetting.value = false;
  }
};

const onContactToggle = async disabled => {
  if (!props.canManageRecords || !contact.value?.id || isSavingContact.value)
    return;
  isSavingContact.value = true;
  try {
    await ContactAPI.update(contact.value.id, {
      additional_attributes: { [CONTACT_FOLLOWUP_DISABLED_KEY]: disabled },
    });
    emit('reset');
  } catch {
    useAlert(label('CONTACT_TOGGLE_ERROR'));
  } finally {
    isSavingContact.value = false;
  }
};

const onResetClick = () => {
  if (!props.canManageAi) return;
  if (isOptedOut.value) {
    reactivateDialogRef.value?.open();
    return;
  }
  resetCycle();
};
</script>

<template>
  <details
    :open="detailsOpen"
    class="group rounded-xl border border-n-weak bg-n-surface-1"
    @toggle="detailsOpen = $event.currentTarget.open"
  >
    <summary
      class="flex min-h-11 cursor-pointer list-none items-center justify-between gap-3 rounded-xl px-4 py-3 outline-none hover:bg-n-alpha-2 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand [&::-webkit-details-marker]:hidden"
    >
      <span class="flex min-w-0 items-center gap-2">
        <span class="i-lucide-bot size-4 shrink-0 text-n-slate-11" />
        <span class="truncate text-sm font-medium text-n-slate-12">
          {{ label('TITLE') }}
        </span>
      </span>
      <span
        class="flex shrink-0 items-center gap-2 text-xs font-medium"
        :class="isOptedOut ? 'text-n-amber-11' : 'text-n-slate-11'"
      >
        <span>{{ statusText }}</span>
        <span
          class="i-lucide-chevron-down size-4 text-n-slate-10 transition-transform group-open:rotate-180"
          aria-hidden="true"
        />
      </span>
    </summary>

    <div class="grid gap-3 border-t border-n-weak p-4">
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
        <span>{{ label('OPT_OUT_HINT') }}</span>
      </p>

      <label
        v-if="contact?.id"
        class="mb-0 flex items-center justify-between gap-3 text-xs text-n-slate-11"
      >
        <span>{{ label('CONTACT_TOGGLE') }}</span>
        <Switch
          :model-value="isContactDisabled"
          :disabled="isSavingContact || !canManageRecords"
          @update:model-value="onContactToggle"
        />
      </label>

      <div
        v-if="canManageAi && (isSpent || isOptedOut)"
        class="flex justify-end"
      >
        <Button
          :label="resetButtonLabel"
          icon="i-lucide-rotate-ccw"
          slate
          faded
          sm
          class="min-w-max shrink-0"
          :is-loading="isResetting"
          @click="onResetClick"
        />
      </div>
    </div>

    <Dialog
      ref="reactivateDialogRef"
      type="alert"
      :title="label('REACTIVATE_CONFIRM_TITLE')"
      :description="label('REACTIVATE_CONFIRM_BODY')"
      :confirm-button-label="label('REACTIVATE_CONFIRM_OK')"
      :is-loading="isResetting"
      :disable-confirm-button="isResetting || !canManageAi"
      @confirm="resetCycle"
    />
  </details>
</template>
