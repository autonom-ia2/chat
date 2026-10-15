<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { convertSecondsToTimeUnit } from '@chatwoot/utils';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { useCanManage } from 'dashboard/composables/useCanManage';
import { SLA_MANAGE_PERMISSION } from 'dashboard/constants/permissions.js';
import {
  BaseTable,
  BaseTableRow,
  BaseTableCell,
} from 'dashboard/components-next/table';
import Button from 'dashboard/components-next/button/Button.vue';
import CrmSlaPolicyDialog from './CrmSlaPolicyDialog.vue';

defineProps({
  pipelines: { type: Array, default: () => [] },
});

const { t } = useI18n();
const store = useStore();

const records = useMapGetter('sla/getSLA');
const uiFlags = useMapGetter('sla/getUIFlags');

// The SLA policy API writes only with sla_manage (SlaPolicyPolicy); a crm_admin seat without it
// reads the list (#1618). Administrators and seats without a custom role keep every action.
const canManage = useCanManage(SLA_MANAGE_PERMISSION);

const showDialog = ref(false);
const selectedPolicy = ref(null);
const deleteCandidate = ref(null);

const tableHeaders = computed(() => [
  t('CRM_SLA.POLICIES.TABLE.NAME'),
  t('CRM_SLA.POLICIES.TABLE.BUSINESS_HOURS'),
  t('CRM_SLA.POLICIES.TABLE.FRT'),
  t('CRM_SLA.POLICIES.TABLE.NRT'),
  t('CRM_SLA.POLICIES.TABLE.RT'),
  t('CRM_SLA.POLICIES.TABLE.AUTO_APPLY'),
  ...(canManage.value ? [t('CRM_SLA.POLICIES.TABLE.ACTIONS')] : []),
]);

// Same compact rendering as the native SLA list (30m / 2h / 1d).
const displayTime = threshold => {
  const { time, unit } = convertSecondsToTimeUnit(threshold, {
    minute: 'm',
    hour: 'h',
    day: 'd',
  });
  if (!time) return '-';
  return `${time}${unit}`;
};

const badgeLabel = enabled =>
  enabled
    ? t('CRM_SLA.POLICIES.BADGES.ENABLED')
    : t('CRM_SLA.POLICIES.BADGES.DISABLED');

const badgeClass = enabled =>
  enabled ? 'bg-n-teal-3 text-n-teal-11' : 'bg-n-alpha-2 text-n-slate-11';

const openCreateDialog = () => {
  selectedPolicy.value = null;
  showDialog.value = true;
};

const openEditDialog = policy => {
  selectedPolicy.value = policy;
  showDialog.value = true;
};

const closeDialog = () => {
  showDialog.value = false;
  selectedPolicy.value = null;
};

const confirmDelete = async () => {
  const { id } = deleteCandidate.value;
  try {
    await store.dispatch('sla/delete', id);
    useAlert(t('CRM_SLA.POLICIES.API.DELETE_SUCCESS'));
  } catch (error) {
    useAlert(t('CRM_SLA.POLICIES.API.DELETE_ERROR'));
  } finally {
    deleteCandidate.value = null;
  }
};
</script>

<template>
  <div class="grid gap-4">
    <div class="flex items-start justify-between gap-3">
      <div class="min-w-0">
        <h3 class="mb-1 text-sm font-medium text-n-slate-12">
          {{ t('CRM_SLA.POLICIES.TITLE') }}
        </h3>
        <p class="mb-0 text-xs leading-5 text-n-slate-11">
          {{ t('CRM_SLA.POLICIES.DESCRIPTION') }}
        </p>
      </div>
      <Button
        v-if="canManage"
        :label="t('CRM_SLA.POLICIES.ADD')"
        icon="i-lucide-plus"
        sm
        @click="openCreateDialog"
      />
    </div>

    <BaseTable
      :headers="tableHeaders"
      :items="records"
      :loading="uiFlags.isFetching"
      :no-data-message="t('CRM_SLA.POLICIES.EMPTY')"
    >
      <template #row="{ items }">
        <BaseTableRow v-for="sla in items" :key="sla.id" :item="sla">
          <BaseTableCell>
            <div class="flex min-w-0 flex-col gap-1">
              <span class="truncate text-body-main text-n-slate-12">
                {{ sla.name }}
              </span>
              <span
                v-if="sla.description"
                class="line-clamp-1 text-body-main text-n-slate-11"
              >
                {{ sla.description }}
              </span>
              <div class="flex flex-wrap items-center gap-1">
                <span
                  v-if="sla.exclude_groups"
                  class="rounded-md bg-n-alpha-2 px-1.5 py-0.5 text-xs text-n-slate-11"
                >
                  {{ t('CRM_SLA.POLICIES.BADGES.GROUPS_EXCLUDED') }}
                </span>
                <span
                  v-if="sla.ai_skip_natural_pause"
                  class="rounded-md bg-n-alpha-2 px-1.5 py-0.5 text-xs text-n-slate-11"
                >
                  {{ t('CRM_SLA.POLICIES.BADGES.AI_GUARD') }}
                </span>
              </div>
            </div>
          </BaseTableCell>

          <BaseTableCell class="w-32">
            <span
              class="rounded-md px-2 py-1 text-xs"
              :class="badgeClass(sla.only_during_business_hours)"
            >
              {{ badgeLabel(sla.only_during_business_hours) }}
            </span>
          </BaseTableCell>

          <BaseTableCell class="w-20">
            <span class="text-body-main text-n-slate-12">
              {{ displayTime(sla.first_response_time_threshold) }}
            </span>
          </BaseTableCell>

          <BaseTableCell class="w-20">
            <span class="text-body-main text-n-slate-12">
              {{ displayTime(sla.next_response_time_threshold) }}
            </span>
          </BaseTableCell>

          <BaseTableCell class="w-20">
            <span class="text-body-main text-n-slate-12">
              {{ displayTime(sla.resolution_time_threshold) }}
            </span>
          </BaseTableCell>

          <BaseTableCell class="w-28">
            <span
              class="rounded-md px-2 py-1 text-xs"
              :class="badgeClass(sla.auto_apply?.enabled)"
            >
              {{ badgeLabel(sla.auto_apply?.enabled) }}
            </span>
          </BaseTableCell>

          <BaseTableCell v-if="canManage" class="w-20">
            <div class="flex items-center gap-1">
              <Button
                icon="i-lucide-pencil"
                slate
                ghost
                sm
                @click="openEditDialog(sla)"
              />
              <Button
                icon="i-lucide-trash-2"
                ruby
                ghost
                sm
                :is-loading="uiFlags.isDeleting"
                @click="deleteCandidate = sla"
              />
            </div>
          </BaseTableCell>
        </BaseTableRow>
      </template>
    </BaseTable>

    <CrmSlaPolicyDialog
      v-if="showDialog"
      :policy="selectedPolicy"
      :pipelines="pipelines"
      @close="closeDialog"
      @saved="closeDialog"
    />

    <div
      v-if="deleteCandidate"
      class="fixed inset-0 z-50 flex items-center justify-center bg-n-alpha-black2 p-4"
      @click.self="deleteCandidate = null"
    >
      <div
        class="flex w-[26rem] max-w-full flex-col gap-4 rounded-xl border border-n-weak bg-n-surface-2 p-6 shadow-lg"
      >
        <h2 class="m-0 text-lg font-medium text-n-slate-12">
          {{ t('CRM_SLA.POLICIES.DELETE.TITLE') }}
        </h2>
        <p class="m-0 text-sm leading-5 text-n-slate-11">
          {{
            t('CRM_SLA.POLICIES.DELETE.MESSAGE', {
              name: deleteCandidate.name,
            })
          }}
        </p>
        <div class="flex items-center justify-end gap-2">
          <Button
            :label="t('CRM_SLA.POLICIES.DELETE.CANCEL')"
            slate
            faded
            @click="deleteCandidate = null"
          />
          <Button
            :label="t('CRM_SLA.POLICIES.DELETE.CONFIRM')"
            ruby
            :is-loading="uiFlags.isDeleting"
            @click="confirmDelete"
          />
        </div>
      </div>
    </div>
  </div>
</template>
