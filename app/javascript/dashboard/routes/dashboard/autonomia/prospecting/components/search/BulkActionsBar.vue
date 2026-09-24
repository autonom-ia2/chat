<script setup>
import { useI18n } from 'vue-i18n';
import { useProspectingSearchContext } from '../../composables/useProspectingSearch';

const { t } = useI18n();
const {
  canManage,
  sortedLeads,
  selectedLeadIds,
  hasSelectedLeads,
  bulkAction,
  canCreateCrmCard,
  toggleAllVisibleLeads,
  runBulkAction,
} = useProspectingSearchContext();
</script>

<template>
  <div class="flex flex-wrap items-center justify-between gap-2 text-xs">
    <div class="flex flex-wrap items-center gap-3">
      <button
        type="button"
        class="font-medium text-n-brand hover:underline disabled:cursor-not-allowed disabled:opacity-60"
        :disabled="!sortedLeads.length"
        @click="toggleAllVisibleLeads"
      >
        {{ t('PROSPECTING.SEARCH.SELECT_VISIBLE') }}
      </button>
      <template v-if="hasSelectedLeads">
        <span class="text-n-slate-10">
          {{
            t('PROSPECTING.SEARCH.SELECTED_COUNT', {
              count: selectedLeadIds.length,
            })
          }}
        </span>
        <button
          v-if="canManage"
          type="button"
          class="h-7 rounded-md bg-n-brand px-3 text-xs font-medium text-white disabled:cursor-not-allowed disabled:opacity-60"
          :disabled="bulkAction === 'crm_cards' || !canCreateCrmCard"
          @click="runBulkAction('crm_cards')"
        >
          {{ t('PROSPECTING.SEARCH.BULK_CRM_CARDS') }}
        </button>
      </template>
    </div>
    <span class="text-n-slate-10">
      {{
        t('PROSPECTING.SEARCH.VISIBLE_COUNT', {
          count: sortedLeads.length,
        })
      }}
    </span>
  </div>
</template>
