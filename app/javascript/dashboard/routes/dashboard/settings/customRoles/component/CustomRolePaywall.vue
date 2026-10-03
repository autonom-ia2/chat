<script setup>
import { computed } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';
import { useRouter } from 'vue-router';
import BasePaywallModal from 'dashboard/routes/dashboard/settings/components/BasePaywallModal.vue';
import CustomRoleCard from './CustomRoleCard.vue';

const dummyCustomRolesData = [
  {
    id: 1,
    name: 'All Permissions',
    description: 'All permissions',
    permissions: [
      'conversation_manage',
      'conversation_participating_manage',
      'conversation_unassigned_manage',
      'contact_manage',
      'report_manage',
      'knowledge_base_manage',
    ],
  },
  {
    id: 2,
    name: 'Conversation Permissions',
    description: 'Conversation permissions',
    permissions: [
      'conversation_manage',
      'conversation_participating_manage',
      'conversation_unassigned_manage',
    ],
  },
  {
    id: 3,
    name: 'Contact Permissions',
    description: 'Contact permissions',
    permissions: ['contact_manage'],
  },
  {
    id: 4,
    name: 'Report Permissions',
    description: 'Report permissions',
    permissions: ['report_manage'],
  },
];

const router = useRouter();

const isOnChatwootCloud = useMapGetter('globalConfig/isOnChatwootCloud');

const currentUser = useMapGetter('getCurrentUser');
const currentAccountId = useMapGetter('getCurrentAccountId');

const isSuperAdmin = computed(() => {
  return currentUser.value.type === 'SuperAdmin';
});
const i18nKey = computed(() =>
  isOnChatwootCloud.value ? 'PAYWALL' : 'ENTERPRISE_PAYWALL'
);

const goToBillingSettings = () => {
  router.push({
    name: 'billing_settings_index',
    params: { accountId: currentAccountId.value },
  });
};
</script>

<template>
  <div class="w-full min-h-[12rem] relative">
    <div inert class="grid gap-3 sm:grid-cols-2 opacity-25 dark:opacity-20">
      <CustomRoleCard
        v-for="role in dummyCustomRolesData"
        :key="role.id"
        :role="role"
      />
    </div>
    <div
      class="absolute inset-0 flex flex-col items-center justify-center w-full h-full bg-gradient-to-t from-white dark:from-slate-900 to-transparent"
    >
      <BasePaywallModal
        feature-prefix="CUSTOM_ROLE"
        :i18n-key="i18nKey"
        :is-on-chatwoot-cloud="isOnChatwootCloud"
        :is-super-admin="isSuperAdmin"
        @upgrade="goToBillingSettings"
      />
    </div>
  </div>
</template>
