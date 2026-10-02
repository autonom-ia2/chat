<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';

import Button from 'dashboard/components-next/button/Button.vue';
import DropdownMenu from 'dashboard/components-next/dropdown-menu/DropdownMenu.vue';
import { usePolicy } from 'dashboard/composables/usePolicy';

const props = defineProps({
  campaignImportEnabled: { type: Boolean, default: false },
});

const emit = defineEmits([
  'add',
  'import',
  'export',
  'campaignImport',
  'campaignImportHistory',
]);

const { t } = useI18n();
const { checkPermissions } = usePolicy();

const contactMenuItems = computed(() => [
  ...(checkPermissions(['administrator', 'agent', 'contact_manage'])
    ? [
        {
          label: t(
            'CONTACTS_LAYOUT.HEADER.ACTIONS.CONTACT_CREATION.ADD_CONTACT'
          ),
          action: 'add',
          value: 'add',
          icon: 'i-lucide-plus',
        },
      ]
    : []),
  ...(checkPermissions(['administrator', 'contact_manage'])
    ? [
        {
          label: t(
            'CONTACTS_LAYOUT.HEADER.ACTIONS.CONTACT_CREATION.EXPORT_CONTACT'
          ),
          action: 'export',
          value: 'export',
          icon: 'i-lucide-upload',
        },
      ]
    : []),
  ...(checkPermissions(['administrator', 'contact_manage'])
    ? [
        {
          label: t(
            'CONTACTS_LAYOUT.HEADER.ACTIONS.CONTACT_CREATION.IMPORT_CONTACT'
          ),
          action: 'import',
          value: 'import',
          icon: 'i-lucide-download',
        },
      ]
    : []),
  ...(props.campaignImportEnabled
    ? [
        {
          label: t('CAMPAIGN_IMPORT.ACTIONS.IMPORT_BASE'),
          action: 'campaignImport',
          value: 'campaignImport',
          icon: 'i-lucide-tags',
        },
        {
          label: t('CAMPAIGN_IMPORT.ACTIONS.HISTORY'),
          action: 'campaignImportHistory',
          value: 'campaignImportHistory',
          icon: 'i-lucide-history',
        },
      ]
    : []),
]);
const showActionsDropdown = ref(false);

const handleContactAction = ({ action }) => {
  if (action === 'add') {
    emit('add');
  } else if (action === 'import') {
    emit('import');
  } else if (action === 'export') {
    emit('export');
  } else if (action === 'campaignImport') {
    emit('campaignImport');
  } else if (action === 'campaignImportHistory') {
    emit('campaignImportHistory');
  }
};
</script>

<template>
  <div
    v-if="contactMenuItems.length"
    v-on-clickaway="() => (showActionsDropdown = false)"
    class="relative"
  >
    <Button
      icon="i-lucide-ellipsis-vertical"
      color="slate"
      variant="ghost"
      size="sm"
      :class="showActionsDropdown ? 'bg-n-alpha-2' : ''"
      @click="showActionsDropdown = !showActionsDropdown"
    />
    <DropdownMenu
      v-if="showActionsDropdown"
      :menu-items="contactMenuItems"
      class="ltr:right-0 rtl:left-0 mt-1 w-52 top-full"
      @action="handleContactAction($event)"
    />
  </div>
  <template v-else />
</template>
