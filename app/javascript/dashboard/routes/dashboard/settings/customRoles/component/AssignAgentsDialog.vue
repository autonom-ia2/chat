<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';

const emit = defineEmits(['done']);

const store = useStore();
const { t } = useI18n();
const agents = useMapGetter('agents/getAgents');

const dialogRef = ref(null);
const role = ref(null);
const selected = ref([]);
const isSaving = ref(false);
let isDone = false;

// Dialog emits close more than once (our call plus the native event); report it once.
const onClose = () => {
  if (isDone) return;
  isDone = true;
  emit('done');
};

// Administrators keep full access; a custom role would only hide their admin screens.
const candidates = computed(() =>
  agents.value.filter(agent => agent.role === 'agent')
);

const toggle = id => {
  selected.value = selected.value.includes(id)
    ? selected.value.filter(item => item !== id)
    : [...selected.value, id];
};

const open = createdRole => {
  role.value = createdRole;
  selected.value = [];
  isDone = false;
  dialogRef.value?.open();
};

const finish = () => dialogRef.value?.close();

const assign = async () => {
  if (!selected.value.length) return finish();
  isSaving.value = true;
  const results = await Promise.allSettled(
    candidates.value
      .filter(agent => selected.value.includes(agent.id))
      .map(agent =>
        store.dispatch('agents/update', {
          id: agent.id,
          name: agent.name,
          custom_role_id: role.value.id,
        })
      )
  );
  isSaving.value = false;
  const failed = results.filter(result => result.status === 'rejected').length;
  useAlert(
    failed
      ? t('CUSTOM_ROLE.ASSIGN.PARTIAL_ERROR', { count: failed })
      : t('CUSTOM_ROLE.ASSIGN.SUCCESS', selected.value.length)
  );
  return finish();
};

defineExpose({ open });
</script>

<template>
  <Dialog
    ref="dialogRef"
    :title="t('CUSTOM_ROLE.ASSIGN.TITLE', { name: role?.name || '' })"
    :description="t('CUSTOM_ROLE.ASSIGN.DESCRIPTION')"
    :confirm-button-label="
      selected.length
        ? t('CUSTOM_ROLE.ASSIGN.CONFIRM', selected.length)
        : t('CUSTOM_ROLE.ASSIGN.LATER')
    "
    :cancel-button-label="t('CUSTOM_ROLE.ASSIGN.LATER')"
    :show-cancel-button="selected.length > 0"
    :is-loading="isSaving"
    overflow-y-auto
    @confirm="assign"
    @close="onClose"
  >
    <p v-if="!candidates.length" class="m-0 text-sm text-n-slate-11">
      {{ t('CUSTOM_ROLE.ASSIGN.EMPTY') }}
    </p>
    <ul
      v-else
      class="grid p-0 m-0 overflow-hidden list-none rounded-lg gap-px max-h-72 overflow-y-auto bg-n-weak outline outline-1 outline-n-weak"
    >
      <li
        v-for="agent in candidates"
        :key="agent.id"
        class="flex items-center gap-3 px-3 py-2 bg-n-solid-1"
      >
        <Avatar
          :name="agent.name"
          :src="agent.thumbnail"
          :size="28"
          rounded-full
        />
        <span class="flex-1 min-w-0">
          <span class="block text-sm truncate text-n-slate-12">
            {{ agent.name }}
          </span>
          <span
            v-if="agent.custom_role_id && agent.custom_role_id !== role?.id"
            class="block text-label-small text-n-amber-11"
          >
            {{ t('CUSTOM_ROLE.ASSIGN.REPLACES') }}
          </span>
        </span>
        <Switch
          :model-value="selected.includes(agent.id)"
          :aria-label="t('CUSTOM_ROLE.ASSIGN.TOGGLE', { name: agent.name })"
          @update:model-value="toggle(agent.id)"
        />
      </li>
    </ul>
  </Dialog>
</template>
