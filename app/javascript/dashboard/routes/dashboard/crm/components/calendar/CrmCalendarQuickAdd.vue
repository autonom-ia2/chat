<script setup>
import { ref, computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { format } from 'date-fns';
import { ptBR, enUS } from 'date-fns/locale';

import CrmKanbanAPI from 'dashboard/api/crmKanban';
import crmBookingPagesAPI from 'dashboard/api/crmBookingPages';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';

const props = defineProps({
  show: { type: Boolean, default: false },
  // The calendar day the user clicked (drives the pre-filled date).
  date: { type: [Date, String, Number], default: () => new Date() },
  // Active funnel — scopes the deal search.
  pipelineId: { type: [String, Number], default: null },
  defaultType: { type: String, default: 'reminder' },
  meetingsEnabled: { type: Boolean, default: false },
  // Agendamento novo ligado na conta (`isBookingV2Available`).
  bookingV2: { type: Boolean, default: false },
});

const emit = defineEmits(['create', 'moreOptions', 'scheduleMeeting', 'close']);

const { t, locale } = useI18n();

const dialogRef = ref(null);
const dateFnsLocale = computed(() => (locale.value === 'pt_BR' ? ptBR : enUS));

/* -------------------------------------------------------------------------- */
/* Type — reminder works as a fast quick-save; richer types defer to a full flow. */
/* -------------------------------------------------------------------------- */
const TYPES = [
  {
    key: 'reminder',
    icon: 'i-lucide-bell',
    quick: true,
    labelKey: 'CRM_KANBAN.CALENDAR.TYPE.REMINDER',
  },
  {
    key: 'whatsapp',
    icon: 'i-lucide-message-circle',
    quick: false,
    labelKey: 'CRM_KANBAN.CALENDAR.TYPE.WHATSAPP',
  },
  {
    key: 'closeDate',
    icon: 'i-lucide-target',
    quick: false,
    labelKey: 'CRM_KANBAN.CALENDAR.TYPE.CLOSE',
  },
  {
    key: 'meeting',
    icon: 'i-lucide-users',
    quick: false,
    labelKey: 'CRM_KANBAN.CALENDAR.TYPE.MEETING',
  },
];
const type = ref(props.defaultType);
const availableTypes = computed(() =>
  props.meetingsEnabled ? TYPES : TYPES.filter(item => item.key !== 'meeting')
);
const activeType = computed(() => TYPES.find(item => item.key === type.value));
const resolveType = value =>
  availableTypes.value.some(item => item.key === value) ? value : 'reminder';

/* -------------------------------------------------------------------------- */
/* Form state                                                                 */
/* -------------------------------------------------------------------------- */
const title = ref('');
const cardId = ref('');
const selectedCardLabel = ref('');
const pickedDate = ref(new Date());

const toDate = value => {
  if (value instanceof Date) return value;
  if (typeof value === 'number') return new Date(value);
  return value ? new Date(value) : new Date();
};

/* ------------------------------ Deal search ------------------------------- */
const dealOptions = ref([]);
const isSearching = ref(false);
// Monotonic token so a slow earlier response never clobbers a newer query.
let searchSeq = 0;

const searchDeals = async query => {
  const term = (query || '').trim();
  if (term.length < 2) {
    dealOptions.value = [];
    return;
  }
  searchSeq += 1;
  const seq = searchSeq;
  isSearching.value = true;
  try {
    const { data } = await CrmKanbanAPI.getCards({
      search: term,
      pipeline_id: props.pipelineId || undefined,
      per_page: 8,
    });
    if (seq !== searchSeq) return;
    dealOptions.value = (data?.payload || []).map(card => ({
      value: card.id,
      label: card.title || `#${card.id}`,
    }));
  } catch (error) {
    dealOptions.value = [];
  } finally {
    isSearching.value = false;
  }
};

const onDealSelected = value => {
  cardId.value = value;
  const match = dealOptions.value.find(option => option.value === value);
  if (match) selectedCardLabel.value = match.label;
};

/* ------------------------------ Time picker ------------------------------- */
const TIME_PRESETS = ['09:00', '12:00', '15:00', '18:00'];
const selectedTime = ref('09:00');
const showCustomTime = ref(false);

// 15-min increments — a type-to-filter list (Google Calendar pattern), 24h
// labels so pt_BR never shows AM/PM.
const timeOptions = computed(() => {
  const out = [];
  for (let h = 0; h < 24; h += 1) {
    for (let m = 0; m < 60; m += 15) {
      const value = `${String(h).padStart(2, '0')}:${String(m).padStart(2, '0')}`;
      out.push({ value, label: value });
    }
  }
  return out;
});

const onPresetTime = value => {
  selectedTime.value = value;
  showCustomTime.value = false;
};
const onCustomToggle = () => {
  showCustomTime.value = true;
};

/* Reset every time the dialog is (re)opened on a fresh day. */
watch(
  () => props.show,
  isOpen => {
    if (isOpen) {
      type.value = resolveType(props.defaultType);
      title.value = '';
      cardId.value = '';
      selectedCardLabel.value = '';
      pickedDate.value = toDate(props.date);
      selectedTime.value = '09:00';
      showCustomTime.value = false;
      dealOptions.value = [];
      dialogRef.value?.open();
    } else {
      dialogRef.value?.close();
    }
  }
);

watch(
  () => props.meetingsEnabled,
  () => {
    type.value = resolveType(type.value);
  }
);

/* ------------------------------ Derived ----------------------------------- */
const dateLabel = computed(() =>
  format(pickedDate.value, "EEEE, d 'de' MMMM", { locale: dateFnsLocale.value })
);

const dueAt = computed(() => {
  const [h, m] = (selectedTime.value || '09:00').split(':').map(Number);
  const d = new Date(pickedDate.value);
  d.setHours(h || 0, m || 0, 0, 0);
  return d;
});

const buildMoreOptionsPayload = () => ({
  cardId: cardId.value,
  type: type.value,
  date: dueAt.value,
});

const emitScheduleMeeting = () =>
  emit('scheduleMeeting', buildMoreOptionsPayload());

const onTypeSelected = item => {
  type.value = item.key;
  if (item.key === 'meeting' && cardId.value) emitScheduleMeeting();
};

const isQuickType = computed(() => activeType.value?.quick === true);

const canSave = computed(() => {
  // Non-quick types open the chosen deal's card — a deal must be selected.
  if (!isQuickType.value) return !!cardId.value;
  return (
    title.value.trim().length > 0 && !!cardId.value && !!selectedTime.value
  );
});

const confirmLabel = computed(() => {
  if (isQuickType.value) return t('CRM_KANBAN.CALENDAR.QUICK_ADD.SAVE');
  return t('CRM_KANBAN.CALENDAR.QUICK_ADD.CONTINUE');
});

// Dica da reunião (#1285): com o agendamento novo e uma página que serve (o
// mesmo critério da janela seguinte para abrir a agenda), o Continuar leva aos
// dias e horários livres, e a dica diz isso. Sem a flag ou sem página, a
// janela seguinte é a do Google/Microsoft e a dica antiga continua.
const hasAgenda = ref(false);
const isCheckingAgenda = ref(false);
let agendaRequest = 0;
const checkAgenda = async () => {
  agendaRequest += 1;
  const current = agendaRequest;
  hasAgenda.value = false;
  isCheckingAgenda.value = false;
  if (!props.show || !props.bookingV2 || type.value !== 'meeting') return;

  isCheckingAgenda.value = true;
  try {
    const { data } = await crmBookingPagesAPI.bookable();
    if (current !== agendaRequest) return;
    hasAgenda.value = (data?.payload || []).length > 0;
  } catch {
    // Sem acesso ou com falha, fica a dica antiga; a janela seguinte mostra
    // o erro dela, com "Tentar de novo".
  } finally {
    if (current === agendaRequest) isCheckingAgenda.value = false;
  }
};
watch(() => [props.show, props.bookingV2, type.value], checkAgenda);

// Meeting → Continuar opens the scheduler (not the card), so the hint differs.
const advancedHintKey = computed(() => {
  if (type.value !== 'meeting') {
    return 'CRM_KANBAN.CALENDAR.QUICK_ADD.ADVANCED_HINT';
  }
  return hasAgenda.value
    ? 'CRM_KANBAN.CALENDAR.QUICK_ADD.MEETING_HINT_AGENDA'
    : 'CRM_KANBAN.CALENDAR.QUICK_ADD.MEETING_HINT';
});

const onConfirm = () => {
  if (!canSave.value) return;
  if (!isQuickType.value) {
    if (type.value === 'meeting') emitScheduleMeeting();
    else emit('moreOptions', buildMoreOptionsPayload());
    return;
  }
  emit('create', {
    type: type.value,
    cardId: cardId.value,
    title: title.value.trim(),
    dueAt: dueAt.value.toISOString(),
  });
};

const onMoreOptions = () => {
  if (type.value === 'meeting') emitScheduleMeeting();
  else emit('moreOptions', buildMoreOptionsPayload());
};
const onClose = () => emit('close');
</script>

<template>
  <Dialog
    ref="dialogRef"
    :title="t('CRM_KANBAN.CALENDAR.QUICK_ADD.NEW_REMINDER')"
    width="md"
    :confirm-button-label="confirmLabel"
    :disable-confirm-button="!canSave"
    @confirm="onConfirm"
    @close="onClose"
  >
    <div class="flex flex-col gap-4">
      <p class="-mt-2 mb-0 flex items-center gap-1.5 text-xs text-n-slate-11">
        <span class="i-lucide-calendar size-3.5" />
        <span class="capitalize">{{ dateLabel }}</span>
      </p>

      <!-- Type -->
      <fieldset class="flex flex-col gap-1.5">
        <legend class="mb-1 text-xs font-medium text-n-slate-11">
          {{ t('CRM_KANBAN.CALENDAR.QUICK_ADD.TYPE_LABEL') }}
        </legend>
        <div class="flex gap-2">
          <button
            v-for="item in availableTypes"
            :key="item.key"
            type="button"
            class="flex flex-1 items-center justify-center gap-1.5 rounded-lg px-2 py-1.5 text-xs font-medium outline-1 transition-colors"
            :class="
              type === item.key
                ? 'bg-n-brand/10 text-n-blue-11 outline-n-brand'
                : 'bg-n-alpha-1 text-n-slate-11 outline-transparent hover:bg-n-alpha-2'
            "
            @click="onTypeSelected(item)"
          >
            <span :class="item.icon" class="size-3.5" />
            {{ t(item.labelKey) }}
          </button>
        </div>
      </fieldset>

      <!-- Title -->
      <Input
        v-model="title"
        :label="t('CRM_KANBAN.CALENDAR.QUICK_ADD.TITLE_LABEL')"
        :placeholder="t('CRM_KANBAN.CALENDAR.QUICK_ADD.TITLE_PLACEHOLDER')"
        autofocus
      />

      <!-- Deal (negócio) — required -->
      <div class="flex flex-col gap-1.5">
        <span
          class="text-xs font-medium text-n-slate-11 after:ml-0.5 after:text-n-ruby-11 after:content-['*']"
        >
          {{ t('CRM_KANBAN.CALENDAR.QUICK_ADD.DEAL_LABEL') }}
        </span>
        <ComboBox
          :model-value="cardId"
          :options="dealOptions"
          :display-label="selectedCardLabel"
          use-api-results
          :placeholder="t('CRM_KANBAN.CALENDAR.QUICK_ADD.DEAL_PLACEHOLDER')"
          :search-placeholder="t('CRM_KANBAN.CALENDAR.QUICK_ADD.DEAL_SEARCH')"
          @update:model-value="onDealSelected"
          @search="searchDeals"
        />
      </div>

      <!-- When — date is fixed to the clicked day; pick a time -->
      <fieldset class="flex flex-col gap-1.5">
        <legend class="mb-1 text-xs font-medium text-n-slate-11">
          {{ t('CRM_KANBAN.CALENDAR.QUICK_ADD.TIME_LABEL') }}
        </legend>
        <div class="flex flex-wrap items-center gap-2">
          <button
            v-for="preset in TIME_PRESETS"
            :key="preset"
            type="button"
            class="rounded-lg px-2.5 py-1 text-xs font-medium outline-1 tabular-nums transition-colors"
            :class="
              !showCustomTime && selectedTime === preset
                ? 'bg-n-brand text-white outline-n-brand'
                : 'bg-n-alpha-1 text-n-slate-11 outline-transparent hover:bg-n-alpha-2'
            "
            @click="onPresetTime(preset)"
          >
            {{ preset }}
          </button>
          <button
            type="button"
            class="rounded-lg px-2.5 py-1 text-xs font-medium outline-1 transition-colors"
            :class="
              showCustomTime
                ? 'bg-n-brand text-white outline-n-brand'
                : 'bg-n-alpha-1 text-n-slate-11 outline-transparent hover:bg-n-alpha-2'
            "
            @click="onCustomToggle"
          >
            {{ t('CRM_KANBAN.CALENDAR.QUICK_ADD.TIME_OTHER') }}
          </button>
        </div>
        <ComboBox
          v-if="showCustomTime"
          v-model="selectedTime"
          :options="timeOptions"
          :placeholder="t('CRM_KANBAN.CALENDAR.QUICK_ADD.TIME_PLACEHOLDER')"
          class="mt-1"
        />
      </fieldset>

      <p
        v-if="!isQuickType && !isCheckingAgenda"
        class="mb-0 rounded-lg bg-n-alpha-1 px-3 py-2 text-xs text-n-slate-11"
        data-quick-add-hint
      >
        {{ t(advancedHintKey) }}
      </p>
    </div>

    <template #footer>
      <div class="flex w-full items-center justify-between gap-3">
        <button
          type="button"
          class="text-xs font-medium text-n-blue-11 hover:underline"
          @click="onMoreOptions"
        >
          {{ t('CRM_KANBAN.CALENDAR.QUICK_ADD.MORE_OPTIONS') }}
        </button>
        <div class="flex items-center gap-2">
          <button
            type="button"
            class="rounded-lg bg-n-alpha-2 px-3 py-1.5 text-sm font-medium text-n-slate-12 hover:bg-n-alpha-3"
            @click="onClose"
          >
            {{ t('CRM_KANBAN.CALENDAR.QUICK_ADD.CANCEL') }}
          </button>
          <button
            type="button"
            class="rounded-lg bg-n-brand px-3 py-1.5 text-sm font-medium text-white disabled:opacity-50"
            :disabled="!canSave"
            @click="onConfirm"
          >
            {{ confirmLabel }}
          </button>
        </div>
      </div>
    </template>
  </Dialog>
</template>
