<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import { useMapGetter } from 'dashboard/composables/store';
import { usePeopleAccess } from 'dashboard/composables/usePeopleAccess';

// Excluir uma função com gente (#2185): uma pergunta só, para onde as pessoas vão. Antes elas viravam
// agente comum sem aviso, e agente comum vê quase todo o CRM.
const emit = defineEmits(['confirm']);

const NO_ROLE = 'none';

const { t } = useI18n();
const roles = useMapGetter('customRole/getCustomRoles');
// O servidor só aceita como destino uma função que quem exclui poderia entregar.
const { reachesRole } = usePeopleAccess();

const dialogRef = ref(null);
const role = ref(null);
const count = ref(0);
const destination = ref('');

const options = computed(() => [
  ...roles.value
    .filter(item => item.id !== role.value?.id && reachesRole(item))
    .map(item => ({ value: item.id, label: item.name })),
  {
    value: NO_ROLE,
    label: t('CUSTOM_ROLE.DELETE.MOVE.NO_ROLE'),
    hint: t('CUSTOM_ROLE.DELETE.MOVE.NO_ROLE_HINT'),
  },
]);

const open = (roleToDelete, peopleCount) => {
  role.value = roleToDelete;
  count.value = peopleCount;
  destination.value = '';
  dialogRef.value?.open();
};

const confirm = () => {
  if (destination.value === '') return;
  dialogRef.value?.close();
  emit('confirm', { role: role.value, destinationRoleId: destination.value });
};

defineExpose({ open });
</script>

<template>
  <Dialog
    ref="dialogRef"
    type="alert"
    :title="t('CUSTOM_ROLE.DELETE.MOVE.TITLE', count)"
    :description="
      t('CUSTOM_ROLE.DELETE.MOVE.DESCRIPTION', { name: role?.name || '' })
    "
    :confirm-button-label="t('CUSTOM_ROLE.DELETE.MOVE.CONFIRM')"
    :disable-confirm-button="destination === ''"
    :close-on-outside-click="false"
    @confirm="confirm"
  >
    <ChoiceSelect
      v-model="destination"
      :options="options"
      :aria-label="t('CUSTOM_ROLE.DELETE.MOVE.LABEL')"
      :placeholder="t('CUSTOM_ROLE.DELETE.MOVE.PLACEHOLDER')"
      class="w-full"
    />
    <p
      v-if="destination === NO_ROLE"
      role="alert"
      class="flex items-start gap-2 m-0 text-sm text-n-amber-11"
    >
      <span class="i-lucide-triangle-alert size-4 mt-0.5 shrink-0" />
      {{ t('CUSTOM_ROLE.DELETE.MOVE.NO_ROLE_WARNING') }}
    </p>
  </Dialog>
</template>
