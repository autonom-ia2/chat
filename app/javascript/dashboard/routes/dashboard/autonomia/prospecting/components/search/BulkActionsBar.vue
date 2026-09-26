<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import DiscardLeadsModal from './DiscardLeadsModal.vue';
import { useProspectingSearchContext } from '../../composables/useProspectingSearch';
import { crmSendableLeads } from '../../utils/leadCrmPresence';

const { t } = useI18n();
const {
  canManage,
  canSendToCrm,
  canAddToCampaign,
  sortedLeads,
  selectedLeadIds,
  hasSelectedLeads,
  selectedLeadObjects,
  toggleAllVisibleLeads,
  openCrmSend,
  campaignLeads,
  creatingContacts,
  createContacts,
  discardLeads,
} = useProspectingSearchContext();

// Lead já no CRM ou descartado sai do envio em lote ao CRM (#732): o envio
// leva só o resto, e a barra diz quantos ficaram de fora.
const crmLeads = computed(() => crmSendableLeads(selectedLeadObjects.value));
const crmExcludedCount = computed(
  () => selectedLeadObjects.value.length - crmLeads.value.length
);
const discardTarget = ref(null);

const afterDiscard = () => {
  const discarded = new Set(discardTarget.value.map(lead => Number(lead.id)));
  selectedLeadIds.value = selectedLeadIds.value.filter(
    id => !discarded.has(Number(id))
  );
  discardTarget.value = null;
};
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
          v-if="canSendToCrm"
          type="button"
          class="inline-flex h-7 items-center gap-1.5 rounded-md bg-n-brand px-3 text-xs font-medium text-white disabled:cursor-not-allowed disabled:opacity-60"
          :disabled="!crmLeads.length"
          @click="openCrmSend(crmLeads)"
        >
          <span class="i-lucide-kanban-square size-3.5" aria-hidden="true" />
          {{ t('PROSPECTING.SEARCH.SEND_TO_CRM') }}
        </button>
        <button
          v-if="canAddToCampaign"
          type="button"
          class="inline-flex h-7 items-center gap-1.5 rounded-md border border-n-weak bg-n-solid-1 px-3 text-xs font-medium text-n-slate-12 hover:bg-n-solid-2"
          @click="campaignLeads = selectedLeadObjects"
        >
          <span class="i-lucide-megaphone size-3.5" aria-hidden="true" />
          {{ t('PROSPECTING.SEARCH.ADD_TO_CAMPAIGN') }}
        </button>
        <template v-if="canManage">
          <button
            type="button"
            class="inline-flex h-7 items-center gap-1.5 rounded-md border border-n-weak bg-n-solid-1 px-3 text-xs font-medium text-n-slate-12 hover:bg-n-solid-2 disabled:cursor-not-allowed disabled:opacity-60"
            :disabled="creatingContacts"
            @click="createContacts(selectedLeadObjects)"
          >
            <span class="i-lucide-user-plus size-3.5" aria-hidden="true" />
            {{
              creatingContacts
                ? t('PROSPECTING.BULK.CREATING_CONTACTS')
                : t('PROSPECTING.SEARCH.BULK_CONTACTS')
            }}
          </button>
          <button
            type="button"
            class="inline-flex h-7 items-center gap-1.5 rounded-md border border-n-weak bg-n-solid-1 px-3 text-xs font-medium text-n-ruby-11 hover:bg-n-solid-2"
            @click="discardTarget = selectedLeadObjects"
          >
            <span class="i-lucide-ban size-3.5" aria-hidden="true" />
            {{ t('PROSPECTING.DISCARD.ACTION') }}
          </button>
        </template>
        <span v-if="canSendToCrm && crmExcludedCount" class="text-n-slate-10">
          {{ t('PROSPECTING.BULK.CRM_EXCLUDED', { count: crmExcludedCount }) }}
        </span>
      </template>
    </div>
    <span class="text-n-slate-10">
      {{
        t('PROSPECTING.SEARCH.VISIBLE_COUNT', {
          count: sortedLeads.length,
        })
      }}
    </span>
    <DiscardLeadsModal
      v-if="discardTarget"
      :leads="discardTarget"
      :discard="discardLeads"
      @close="discardTarget = null"
      @discarded="afterDiscard"
    />
  </div>
</template>
