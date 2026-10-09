<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import Breadcrumb from 'dashboard/components-next/breadcrumb/Breadcrumb.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import SettingsLayout from 'dashboard/routes/dashboard/settings/SettingsLayout.vue';
import CrmKanbanAPI from 'dashboard/api/crmKanban';

const { t } = useI18n();
const router = useRouter();

const isLoading = ref(false);
const pipelines = ref([]);

const breadcrumbItems = computed(() => [
  {
    label: t('ASSIGNMENT_POLICY.INDEX.HEADER.TITLE'),
    routeName: 'assignment_policy_index',
  },
  { label: t('CRM_KANBAN.HANDOFF_SETTINGS.INDEX_TITLE') },
]);

const handoffSummary = pipeline => {
  const handoff = pipeline.metadata?.ai?.handoff || {};
  if (handoff.enabled !== true && handoff.enabled !== 'true') {
    return {
      enabled: false,
      label: t('CRM_KANBAN.HANDOFF_SETTINGS.STATUS_OFF'),
    };
  }
  const flowKey =
    handoff.handoff_mode === 'r3_invite' ? 'FLOW_INVITE' : 'FLOW_DIRECT';
  return {
    enabled: true,
    label: t('CRM_KANBAN.HANDOFF_SETTINGS.STATUS_ON', {
      flow: t(`CRM_KANBAN.HANDOFF_SETTINGS.${flowKey}`),
    }),
  };
};

const openPipeline = pipeline => {
  router.push({
    name: 'crm_handoff_settings_edit',
    params: { pipelineId: pipeline.id },
  });
};

const handleBreadcrumbClick = item => {
  if (item.routeName) router.push({ name: item.routeName });
};

onMounted(async () => {
  isLoading.value = true;
  try {
    const response = await CrmKanbanAPI.getPipelines();
    pipelines.value = response.data.payload || [];
  } catch {
    useAlert(t('CRM_KANBAN.HANDOFF_SETTINGS.LOAD_ERROR'));
  } finally {
    isLoading.value = false;
  }
});
</script>

<template>
  <SettingsLayout
    :is-loading="isLoading"
    :no-records-found="!isLoading && pipelines.length === 0"
    :no-records-message="t('CRM_KANBAN.HANDOFF_SETTINGS.NO_PIPELINES')"
  >
    <template #header>
      <div class="flex min-h-10 w-full items-center gap-2">
        <Button
          icon="i-lucide-arrow-left"
          slate
          ghost
          sm
          :aria-label="t('CRM_KANBAN.HANDOFF_SETTINGS.BACK_TO_CRM')"
          @click="router.push({ name: 'crm_kanban_index' })"
        />
        <Breadcrumb :items="breadcrumbItems" @click="handleBreadcrumbClick" />
      </div>
    </template>

    <template #body>
      <div class="grid max-w-3xl gap-3 pt-4">
        <p class="mb-0 text-sm text-n-slate-11">
          {{ t('CRM_KANBAN.HANDOFF_SETTINGS.INDEX_DESCRIPTION') }}
        </p>

        <button
          v-for="pipeline in pipelines"
          :key="pipeline.id"
          type="button"
          class="flex items-center justify-between gap-3 rounded-xl bg-n-alpha-black2 p-4 text-left outline outline-1 outline-n-weak transition-colors hover:outline-n-strong"
          @click="openPipeline(pipeline)"
        >
          <div class="min-w-0">
            <p class="mb-0 truncate text-sm font-medium text-n-slate-12">
              {{ pipeline.name }}
            </p>
            <p
              v-if="pipeline.description"
              class="mb-0 truncate text-xs text-n-slate-11"
            >
              {{ pipeline.description }}
            </p>
          </div>
          <div class="flex shrink-0 items-center gap-2">
            <span
              class="rounded-full px-2.5 py-0.5 text-xs font-medium"
              :class="
                handoffSummary(pipeline).enabled
                  ? 'bg-n-teal-3 text-n-teal-11'
                  : 'bg-n-alpha-2 text-n-slate-11'
              "
            >
              {{ handoffSummary(pipeline).label }}
            </span>
            <span class="i-lucide-chevron-right size-4 text-n-slate-10" />
          </div>
        </button>
      </div>
    </template>
  </SettingsLayout>
</template>
