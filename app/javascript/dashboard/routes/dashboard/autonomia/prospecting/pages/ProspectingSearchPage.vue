<script setup>
import { useI18n } from 'vue-i18n';
import ConfirmModal from 'dashboard/components/widgets/modal/ConfirmationModal.vue';
import ProspectingAiCredentialNotice from '../components/ProspectingAiCredentialNotice.vue';
import ProspectingMockProviderNotice from '../components/ProspectingMockProviderNotice.vue';
import SearchForm from '../components/search/SearchForm.vue';
import SearchHistory from '../components/search/SearchHistory.vue';
import SearchModeBadge from '../components/search/SearchModeBadge.vue';
import SearchResults from '../components/search/SearchResults.vue';
import SearchConfigModal from '../components/search/SearchConfigModal.vue';
import LeadDetailDrawer from '../components/search/LeadDetailDrawer.vue';
import CrmSendModal from '../components/crm/CrmSendModal.vue';
import CampaignSelectionModal from '../components/campaign/CampaignSelectionModal.vue';
import { useProspectingSearch } from '../composables/useProspectingSearch';

const { t } = useI18n();
const {
  canManage,
  settings,
  showNewSearch,
  selectedSearchConfig,
  selectedLeadDetail,
  crmForm,
  crmSendLeads,
  closeCrmSend,
  applyCrmSendResult,
  campaignLeads,
  selectedSearch,
  deleteSearchConfirmModal,
  deleteSearchConfirmConfig,
  toggleNewSearch,
} = useProspectingSearch();
</script>

<template>
  <main
    class="flex h-full min-h-0 w-full flex-col overflow-hidden bg-n-background"
  >
    <header
      class="flex flex-col gap-3 border-b border-n-weak px-6 py-4 sm:flex-row sm:items-center sm:justify-between"
    >
      <div>
        <div class="flex flex-wrap items-center gap-x-3 gap-y-2">
          <h1 class="text-xl font-semibold text-n-slate-12">
            {{ t('PROSPECTING.SEARCH.TITLE') }}
          </h1>
          <SearchModeBadge />
        </div>
        <p class="mt-1 text-sm text-n-slate-10">
          {{ t('PROSPECTING.SEARCH.SUBTITLE') }}
        </p>
      </div>
      <button
        v-if="canManage"
        type="button"
        class="inline-flex h-10 items-center justify-center gap-2 rounded-md bg-n-brand px-4 text-sm font-medium text-white"
        @click="toggleNewSearch"
      >
        <span
          class="size-4"
          :class="showNewSearch ? 'i-lucide-arrow-left' : 'i-lucide-plus'"
        />
        {{
          showNewSearch
            ? t('PROSPECTING.SEARCH.BACK_TO_RESULTS')
            : t('PROSPECTING.SEARCH.NEW_SEARCH')
        }}
      </button>
    </header>

    <section
      class="flex min-h-0 w-full flex-1 flex-col overflow-hidden px-6 py-5"
    >
      <ProspectingMockProviderNotice
        v-if="settings?.mock_provider"
        class="mb-4"
      />
      <ProspectingAiCredentialNotice
        v-if="
          settings?.research_enabled &&
          settings?.ai_credential_configured === false
        "
        class="mb-4"
      />
      <SearchForm v-if="showNewSearch" />

      <div
        v-else
        class="grid min-h-0 w-full flex-1 gap-4 xl:grid-cols-[21rem_minmax(0,1fr)]"
      >
        <SearchHistory />
        <SearchResults />
      </div>
    </section>

    <SearchConfigModal v-if="selectedSearchConfig && !showNewSearch" />

    <LeadDetailDrawer v-if="selectedLeadDetail && !showNewSearch" />

    <CrmSendModal
      v-if="crmSendLeads"
      :leads="crmSendLeads"
      :suggested-pipeline-id="crmForm.pipeline_id"
      :suggested-stage-id="crmForm.stage_id"
      @sent="applyCrmSendResult"
      @close="closeCrmSend"
    />

    <CampaignSelectionModal
      v-if="campaignLeads"
      :leads="campaignLeads"
      :default-segment-name="selectedSearch?.query || ''"
      @close="campaignLeads = null"
    />

    <ConfirmModal
      ref="deleteSearchConfirmModal"
      :title="deleteSearchConfirmConfig.title"
      :description="deleteSearchConfirmConfig.description"
      :confirm-label="deleteSearchConfirmConfig.confirmLabel"
      :cancel-label="t('PROSPECTING.SEARCH.CANCEL')"
    />
  </main>
</template>
