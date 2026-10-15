<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import CrmKanbanAPI from 'dashboard/api/crmKanban';
import { useHasCustomRolePermission } from 'dashboard/composables/useCanManage';
import { CRM_ADMIN_PERMISSION } from 'dashboard/constants/permissions.js';
import CrmSlaPolicyList from '../components/sla/CrmSlaPolicyList.vue';
import CrmInboxScheduleList from '../components/sla/CrmInboxScheduleList.vue';

const { t } = useI18n();
const store = useStore();

const accountId = useMapGetter('getCurrentAccountId');

// SLA is an Enterprise feature: without the account flag the page renders only
// the paywall block and performs no API calls.
const isSlaFeatureEnabled = computed(() =>
  store.getters['accounts/isFeatureEnabledonAccount'](
    accountId.value,
    FEATURE_FLAGS.SLA
  )
);

// Service calendars answer only to administrators and crm_admin seats (Enterprise::Crm::
// ServiceSchedulePolicy). A seat with only sla_manage manages the policies, not the calendars (#1618).
const currentRole = useMapGetter('getCurrentRole');
const hasCrmAdmin = useHasCustomRolePermission(CRM_ADMIN_PERMISSION);
const canManageSchedules = computed(
  () => currentRole.value === 'administrator' || hasCrmAdmin.value
);

const pipelines = ref([]);

onMounted(async () => {
  if (!isSlaFeatureEnabled.value) return;
  store.dispatch('sla/get');
  store.dispatch('inboxes/get');
  try {
    const { data } = await CrmKanbanAPI.getPipelines();
    pipelines.value = data.payload || [];
  } catch (error) {
    pipelines.value = [];
  }
});
</script>

<template>
  <div class="flex flex-col w-full h-full overflow-auto bg-n-background">
    <header class="px-6 py-5 border-b border-n-weak">
      <div class="min-w-0">
        <h1 class="mb-1 text-xl font-semibold text-n-slate-12">
          {{ t('CRM_SLA.HEADER.TITLE') }}
        </h1>
        <p class="m-0 text-sm text-n-slate-11">
          {{ t('CRM_SLA.HEADER.DESCRIPTION') }}
        </p>
      </div>
    </header>

    <div
      v-if="!isSlaFeatureEnabled"
      class="flex flex-col items-center justify-center flex-1 gap-3 p-8 text-center"
    >
      <span class="i-lucide-lock size-8 text-n-slate-10" />
      <h2 class="m-0 text-lg font-medium text-n-slate-12">
        {{ t('CRM_SLA.PAYWALL.TITLE') }}
      </h2>
      <p class="max-w-md m-0 text-sm text-n-slate-11">
        {{ t('CRM_SLA.PAYWALL.DESCRIPTION') }}
      </p>
    </div>

    <div v-else class="flex flex-col gap-6 p-6">
      <section class="p-5 border rounded-xl border-n-weak bg-n-solid-1">
        <CrmSlaPolicyList :pipelines="pipelines" />
      </section>

      <section
        v-if="canManageSchedules"
        class="p-5 border rounded-xl border-n-weak bg-n-solid-1"
      >
        <CrmInboxScheduleList />
      </section>
    </div>
  </div>
</template>
