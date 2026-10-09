<script setup>
import { ref, computed, onMounted, onBeforeUnmount } from 'vue';
import { useI18n } from 'vue-i18n';
import { outcomeLabels, outcomeStatuses } from '../../helpers/cardOutcome';

import Button from 'dashboard/components-next/button/Button.vue';
import SelectMenu from 'dashboard/components-next/selectmenu/SelectMenu.vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';

const props = defineProps({
  count: {
    type: Number,
    default: 0,
  },
  stages: {
    type: Array,
    default: () => [],
  },
  owners: {
    type: Array,
    default: () => [],
  },
  isBusy: {
    type: Boolean,
    default: false,
  },
  // Funil atual: decide os desfechos e os nomes deles (#1144).
  pipeline: {
    type: Object,
    default: null,
  },
});

const emit = defineEmits(['move', 'assign', 'status', 'archive', 'clear']);

const { t } = useI18n();

const confirmDialogRef = ref(null);

const isVisible = computed(() => props.count > 0);

const stageValue = ref('');
const ownerValue = ref('');
const statusValue = ref('');

const stageOptions = computed(() =>
  (props.stages ?? []).map(stage => ({
    value: String(stage.id),
    label: stage.name,
  }))
);

const ownerOptions = computed(() =>
  (props.owners ?? []).map(owner => ({
    value: String(owner.id),
    label: owner.name ?? owner.available_name ?? '',
  }))
);

const statusOptions = computed(() => {
  const statuses = outcomeStatuses(props.pipeline);
  const labels = outcomeLabels(t, props.pipeline);
  return [
    { value: 'open', label: t('CRM_KANBAN.CARD_STATUS.OPEN') },
    { value: statuses.success, label: labels.success },
    { value: statuses.failure, label: labels.failure },
  ];
});

const selectedCountLabel = computed(() =>
  t('CRM_KANBAN.BULK.SELECTED', { count: props.count })
);

const archiveConfirmLabel = computed(() =>
  t('CRM_KANBAN.BULK.DELETE_CONFIRM', { count: props.count })
);

const handleMove = stageId => {
  if (!stageId) return;
  emit('move', { stageId });
  stageValue.value = '';
};

const handleAssign = ownerId => {
  if (!ownerId) return;
  emit('assign', { ownerId });
  ownerValue.value = '';
};

const handleStatus = value => {
  if (!value) return;
  emit('status', { value });
  statusValue.value = '';
};

const requestArchive = () => {
  confirmDialogRef.value?.open();
};

const confirmArchive = () => {
  emit('archive');
  confirmDialogRef.value?.close();
};

const handleClear = () => {
  emit('clear');
};

const handleKeydown = event => {
  if (event.key === 'Escape' && isVisible.value) {
    handleClear();
  }
};

onMounted(() => {
  document.addEventListener('keydown', handleKeydown);
});

onBeforeUnmount(() => {
  document.removeEventListener('keydown', handleKeydown);
});
</script>

<template>
  <Transition
    enter-active-class="transition duration-200 ease-out"
    enter-from-class="translate-y-4 opacity-0"
    enter-to-class="translate-y-0 opacity-100"
    leave-active-class="transition duration-150 ease-in"
    leave-from-class="translate-y-0 opacity-100"
    leave-to-class="translate-y-4 opacity-0"
  >
    <div
      v-if="isVisible"
      class="fixed inset-x-0 bottom-6 z-50 flex justify-center px-4 pointer-events-none"
    >
      <div
        class="flex items-center gap-3 px-4 py-3 rounded-xl shadow-lg pointer-events-auto bg-n-alpha-3 backdrop-blur-[100px] border border-n-weak dark:border-n-strong/50"
      >
        <span class="text-sm font-medium text-n-slate-12 whitespace-nowrap">
          {{ selectedCountLabel }}
        </span>

        <div class="w-px h-6 bg-n-weak" />

        <SelectMenu
          v-model="stageValue"
          :options="stageOptions"
          :label="t('CRM_KANBAN.BULK.MOVE')"
          sub-menu-position="bottom"
          @update:model-value="handleMove"
        />

        <ComboBox
          v-model="ownerValue"
          :options="ownerOptions"
          :placeholder="t('CRM_KANBAN.BULK.ASSIGN')"
          :search-placeholder="t('CRM_KANBAN.LIST.OWNER')"
          :empty-state="t('CRM_KANBAN.LIST.EMPTY_NO_RESULTS')"
          class="!w-40"
          @update:model-value="handleAssign"
        />

        <SelectMenu
          v-model="statusValue"
          :options="statusOptions"
          :label="t('CRM_KANBAN.BULK.STATUS')"
          sub-menu-position="bottom"
          @update:model-value="handleStatus"
        />

        <Button
          variant="ghost"
          color="ruby"
          size="sm"
          icon="i-lucide-archive"
          :label="t('CRM_KANBAN.BULK.DELETE')"
          :is-loading="isBusy"
          :disabled="isBusy"
          @click="requestArchive"
        />

        <div class="w-px h-6 bg-n-weak" />

        <Button
          variant="ghost"
          color="slate"
          size="sm"
          icon="i-lucide-x"
          :label="t('CRM_KANBAN.BULK.CLEAR')"
          :disabled="isBusy"
          @click="handleClear"
        />
      </div>
    </div>
  </Transition>

  <Dialog
    ref="confirmDialogRef"
    type="alert"
    :title="t('CRM_KANBAN.BULK.DELETE')"
    :description="archiveConfirmLabel"
    :confirm-button-label="t('CRM_KANBAN.BULK.DELETE')"
    :is-loading="isBusy"
    @confirm="confirmArchive"
  />
</template>
