<script setup>
import { ref, computed, nextTick, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import {
  cardStatusLabel,
  outcomeLabels,
  outcomeStatuses,
} from '../../helpers/cardOutcome';
import DatePicker from 'vue-datepicker-next';

import Input from 'dashboard/components-next/input/Input.vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
import Button from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  card: {
    type: Object,
    required: true,
  },
  field: {
    type: String,
    required: true,
    validator: value =>
      ['value', 'owner', 'stage', 'status', 'next_follow_up_at'].includes(
        value
      ),
  },
  stages: {
    type: Array,
    default: () => [],
  },
  owners: {
    type: Array,
    default: () => [],
  },
  // Funil atual: decide os desfechos e os nomes deles (#1144).
  pipeline: {
    type: Object,
    default: null,
  },
});

const emit = defineEmits(['save']);

const { t } = useI18n();

const isEditing = ref(false);
const draft = ref(null);

// Normalise a card timestamp that may arrive as an ISO8601 string (list
// payload) or epoch seconds (board/realtime payload) into a JS Date.
const toDate = raw => {
  if (!raw && raw !== 0) return null;
  if (typeof raw === 'number') return new Date(raw * 1000);
  const parsed = new Date(raw);
  return Number.isNaN(parsed.getTime()) ? null : parsed;
};

const STATUS_OPTIONS = computed(() => {
  const statuses = outcomeStatuses(props.pipeline);
  const labels = outcomeLabels(t, props.pipeline);
  return [
    { value: 'open', label: t('CRM_KANBAN.LIST.STATUS_OPEN') },
    { value: statuses.success, label: labels.success },
    { value: statuses.failure, label: labels.failure },
  ];
});

const stageOptions = computed(() =>
  props.stages.map(stage => ({
    value: String(stage.id),
    label: stage.name,
    color: stage.color,
  }))
);

const ownerOptions = computed(() => [
  { value: '', label: t('CRM_KANBAN.CARD.NO_OWNER') },
  ...props.owners.map(owner => ({
    value: String(owner.id),
    label: owner.name,
  })),
]);

const currentStage = computed(() =>
  props.stages.find(stage => Number(stage.id) === Number(props.card.stage_id))
);

const stageLabel = computed(
  () => props.card.stage?.name || currentStage.value?.name || ''
);

const stageColor = computed(
  () => props.card.stage?.color || currentStage.value?.color || null
);

const ownerLabel = computed(
  () => props.card.owner?.name || t('CRM_KANBAN.CARD.NO_OWNER')
);

const statusLabel = computed(() =>
  cardStatusLabel(t, props.card.status, props.pipeline)
);

const followUpDate = computed(() => toDate(props.card.next_follow_up_at));

const followUpLabel = computed(() => {
  const date = followUpDate.value;
  if (!date) return t('CRM_KANBAN.FOLLOW_UP_FILTER.NONE');
  return new Intl.DateTimeFormat(undefined, {
    day: '2-digit',
    month: '2-digit',
    year: 'numeric',
  }).format(date);
});

const followUpBadgeClass = computed(() => {
  const date = followUpDate.value;
  if (!date) return 'text-n-slate-10';
  return date < new Date() ? 'text-n-ruby-11' : 'text-n-teal-11';
});

const formattedValue = computed(() => {
  const cents = props.card.value_cents;
  if (cents === null || cents === undefined) {
    return t('CRM_KANBAN.DRAWER.EMPTY_VALUE');
  }
  return new Intl.NumberFormat(undefined, {
    style: 'currency',
    currency: props.card.currency || 'BRL',
  }).format(Number(cents) / 100);
});

const startEditing = async () => {
  switch (props.field) {
    case 'value':
      draft.value =
        props.card.value_cents === null || props.card.value_cents === undefined
          ? ''
          : Number(props.card.value_cents) / 100;
      break;
    case 'owner':
      draft.value = props.card.owner_id ? String(props.card.owner_id) : '';
      break;
    case 'stage':
      draft.value = props.card.stage_id ? String(props.card.stage_id) : '';
      break;
    case 'status':
      draft.value = props.card.status || 'open';
      break;
    case 'next_follow_up_at':
      draft.value = followUpDate.value;
      break;
    default:
      draft.value = null;
  }
  isEditing.value = true;
  await nextTick();
};

const cancelEditing = () => {
  isEditing.value = false;
  draft.value = null;
};

const commit = value => {
  emit('save', { field: props.field, value });
  isEditing.value = false;
  draft.value = null;
};

const commitValue = () => {
  if (draft.value === '' || draft.value === null) {
    commit(null);
    return;
  }
  commit(Math.round(Number(draft.value) * 100));
};

const commitOwner = value => {
  commit(value === '' ? null : Number(value));
};

const commitStage = value => {
  if (!value || value === String(props.card.stage_id)) {
    cancelEditing();
    return;
  }
  commit(Number(value));
};

const commitStatus = value => {
  if (!value || value === props.card.status) {
    cancelEditing();
    return;
  }
  commit(value);
};

const commitFollowUp = value => {
  if (!value) {
    commit(null);
    return;
  }
  commit(new Date(value).toISOString());
};

// Close the inline editors when the card identity changes underneath us.
watch(
  () => props.card.id,
  () => cancelEditing()
);
</script>

<template>
  <!-- VALUE: inline currency number input -->
  <div v-if="field === 'value'" class="flex w-full min-w-0 justify-end">
    <Input
      v-if="isEditing"
      v-model="draft"
      type="number"
      size="sm"
      autofocus
      min="0"
      class="w-28"
      @enter="commitValue"
      @blur="commitValue"
      @keyup.esc="cancelEditing"
    />
    <button
      v-else
      type="button"
      class="w-full truncate rounded px-1.5 py-1 text-right text-sm text-n-slate-12 hover:bg-n-alpha-2"
      @click.stop="startEditing"
    >
      {{ formattedValue }}
    </button>
  </div>

  <!-- OWNER: ComboBox of agents -->
  <div v-else-if="field === 'owner'" class="flex w-full min-w-0">
    <ComboBox
      v-if="isEditing"
      :model-value="draft"
      :options="ownerOptions"
      class="w-full"
      :placeholder="t('CRM_KANBAN.CARD.NO_OWNER')"
      :search-placeholder="t('CRM_KANBAN.LIST.OWNER')"
      @update:model-value="commitOwner"
    />
    <button
      v-else
      type="button"
      class="w-full truncate rounded px-1.5 py-1 text-left text-sm text-n-slate-11 hover:bg-n-alpha-2"
      @click.stop="startEditing"
    >
      {{ ownerLabel }}
    </button>
  </div>

  <!-- STAGE: colored pill select -->
  <div v-else-if="field === 'stage'" class="flex w-full min-w-0">
    <ComboBox
      v-if="isEditing"
      :model-value="draft"
      :options="stageOptions"
      class="w-full"
      :placeholder="t('CRM_KANBAN.LIST.STAGE')"
      :search-placeholder="t('CRM_KANBAN.LIST.STAGE')"
      @update:model-value="commitStage"
    />
    <button
      v-else
      type="button"
      class="flex min-w-0 items-center gap-1.5 rounded px-1.5 py-1 text-left hover:bg-n-alpha-2"
      @click.stop="startEditing"
    >
      <span
        v-if="stageColor"
        class="size-2 flex-shrink-0 rounded-full"
        :style="{ backgroundColor: stageColor }"
      />
      <span class="truncate text-sm text-n-slate-11">{{ stageLabel }}</span>
    </button>
  </div>

  <!-- STATUS: open/won/lost select -->
  <div v-else-if="field === 'status'" class="flex w-full min-w-0">
    <ComboBox
      v-if="isEditing"
      :model-value="draft"
      :options="STATUS_OPTIONS"
      class="w-full"
      @update:model-value="commitStatus"
    />
    <button
      v-else
      type="button"
      class="w-full truncate rounded px-1.5 py-1 text-left text-sm text-n-slate-11 hover:bg-n-alpha-2"
      @click.stop="startEditing"
    >
      {{ statusLabel }}
    </button>
  </div>

  <!-- NEXT_FOLLOW_UP_AT: date picker -->
  <div v-else-if="field === 'next_follow_up_at'" class="flex w-full min-w-0">
    <div v-if="isEditing" class="flex items-center gap-1">
      <DatePicker
        type="datetime"
        confirm
        clearable
        :editable="false"
        :value="draft"
        :confirm-text="t('CRM_KANBAN.LIST.SAVE')"
        @change="commitFollowUp"
      />
      <Button
        icon="i-lucide-x"
        size="xs"
        variant="ghost"
        color="slate"
        @click.stop="cancelEditing"
      />
    </div>
    <button
      v-else
      type="button"
      class="w-full truncate rounded px-1.5 py-1 text-left text-sm hover:bg-n-alpha-2"
      :class="followUpBadgeClass"
      @click.stop="startEditing"
    >
      {{ followUpLabel }}
    </button>
  </div>
</template>
