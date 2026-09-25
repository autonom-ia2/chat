<script setup>
import { computed } from 'vue';
import { useFixedPanelPresence } from 'dashboard/composables/useFixedPanelState';
import { useI18n } from 'vue-i18n';
import ProspectingPriorityRing from '../ProspectingPriorityRing.vue';
import LeadDetailContact from './LeadDetailContact.vue';
import LeadDetailScore from './LeadDetailScore.vue';
import LeadDetailEnrichment from './LeadDetailEnrichment.vue';
import LeadDetailResearch from './LeadDetailResearch.vue';
import LeadDetailReviews from './LeadDetailReviews.vue';
import { useProspectingSearchContext } from '../../composables/useProspectingSearch';
import {
  leadPrioritySignals,
  priorityTheme,
  priorityValue,
} from '../../utils/prospectingPriority';
import * as formatters from '../../utils/searchFormatters';
import * as detail from '../../utils/leadDetail';

const EMPTY_VALUE = '-';

// Montado só com o lead aberto. Cobre o canto direito, onde fica o lançador do
// Guia (#646): sinaliza enquanto existir, para ele sair de cima dos botões.
useFixedPanelPresence(computed(() => true));

const { t } = useI18n();
const {
  canManage,
  crmStages,
  crmForm,
  selectedLeadDetail,
  selectedLeadDetailId,
  selectedSearch,
  openCrmSend,
  contactUrl,
  crmCardUrl,
  settings,
  researchRequestLeadId,
  requestLeadResearch,
  adoptingOwner,
  adoptOwner,
} = useProspectingSearchContext();

const selectedStageName = computed(() => {
  const stage = crmStages.value.find(
    item => Number(item.id) === Number(crmForm.value.stage_id)
  );
  return stage?.name || t('PROSPECTING.SEARCH.CRM_STAGE_EMPTY');
});
const leadPriority = lead => priorityValue(lead);
const leadPriorityTheme = lead => {
  const priority = leadPriority(lead);
  return priority === null ? null : priorityTheme(priority);
};
const leadSignals = lead =>
  leadPrioritySignals(lead, { t, scoreMode: selectedSearch.value?.score_mode });
const formatLeadAddress = lead => formatters.formatLeadAddress(lead, t);
const googleMapsLeadUrl = lead => formatters.googleMapsLeadUrl(lead, t);
const { leadReviews, negativeFactors } = detail;
const scoreBreakdownEntries = lead => detail.scoreBreakdownEntries(lead, t);
</script>

<template>
  <div
    class="fixed inset-0 z-40 bg-n-slate-12/30"
    @click.self="selectedLeadDetailId = null"
  >
    <aside
      class="ml-auto flex h-full w-full max-w-xl flex-col overflow-hidden border-l border-n-weak bg-n-solid-1 shadow-xl"
    >
      <header
        class="flex items-start justify-between gap-3 border-b border-n-weak px-5 py-4"
      >
        <div class="min-w-0">
          <div class="mb-2 flex flex-wrap items-center gap-2">
            <span
              v-if="selectedLeadDetail.search_rank"
              class="inline-flex items-center rounded-md bg-n-amber-2 px-1.5 py-0.5 text-[11px] font-bold text-n-amber-11 ring-1 ring-n-amber-5"
            >
              {{
                t('PROSPECTING.SEARCH.PRIORITY_GOOGLE_RANK', {
                  rank: selectedLeadDetail.search_rank,
                })
              }}
            </span>
            <span
              v-if="selectedLeadDetail.priority_position"
              class="text-xs text-n-slate-10"
            >
              {{
                t('PROSPECTING.SEARCH.PRIORITY_POSITION_IN_LIST', {
                  position: selectedLeadDetail.priority_position,
                })
              }}
            </span>
            <span
              v-if="selectedLeadDetail.priority_position === 1"
              class="inline-flex items-center gap-1 rounded-full bg-n-teal-2 px-2 py-0.5 text-[11px] font-semibold text-n-teal-11 ring-1 ring-n-teal-5"
            >
              <span class="i-lucide-zap size-3" />
              {{ t('PROSPECTING.SEARCH.PRIORITY_FIRST_CALL') }}
            </span>
          </div>
          <h2 class="break-words text-lg font-semibold text-n-slate-12">
            {{ selectedLeadDetail.name }}
          </h2>
          <p class="mt-1 break-words text-sm text-n-slate-10">
            {{ formatLeadAddress(selectedLeadDetail) || '-' }}
          </p>
        </div>
        <button
          type="button"
          class="flex size-8 shrink-0 items-center justify-center rounded-md text-n-slate-11 hover:bg-n-solid-2"
          :title="t('PROSPECTING.SEARCH.CLOSE_DETAILS')"
          @click="selectedLeadDetailId = null"
        >
          <span class="i-lucide-x size-4" />
        </button>
      </header>

      <div class="min-h-0 flex-1 overflow-y-auto px-5 py-4">
        <section class="grid gap-3">
          <div
            class="rounded-xl border border-n-weak px-5 py-4"
            :class="[
              leadPriorityTheme(selectedLeadDetail)?.cardBg || 'bg-n-solid-2',
            ]"
          >
            <div class="flex items-center gap-4">
              <ProspectingPriorityRing
                :priority="leadPriority(selectedLeadDetail)"
                :size="92"
              />
              <div class="min-w-0 flex-1">
                <p
                  class="text-base font-semibold leading-snug"
                  :class="[
                    leadPriorityTheme(selectedLeadDetail)?.titleClass ||
                      'text-n-slate-12',
                  ]"
                >
                  {{
                    leadPriorityTheme(selectedLeadDetail)?.title ||
                    t('PROSPECTING.SEARCH.FIELDS.PRIORITY')
                  }}
                </p>
                <p class="mt-1 text-sm leading-relaxed text-n-slate-11">
                  {{
                    selectedLeadDetail.human_insight ||
                    t('PROSPECTING.SEARCH.SCORE_BASE', {
                      score: selectedLeadDetail.score || '-',
                    })
                  }}
                </p>
              </div>
            </div>
          </div>

          <div
            v-if="leadSignals(selectedLeadDetail).length"
            class="flex flex-wrap gap-1.5"
          >
            <span
              v-for="signal in leadSignals(selectedLeadDetail)"
              :key="signal.key"
              class="inline-flex items-center gap-1 rounded-full border px-2 py-0.5 text-[11px] font-medium"
              :class="signal.card"
            >
              <span :class="[signal.icon, signal.iconClass]" class="size-3" />
              {{ signal.label }}
            </span>
          </div>

          <LeadDetailScore
            v-if="
              scoreBreakdownEntries(selectedLeadDetail).length ||
              negativeFactors(selectedLeadDetail).length
            "
            :lead="selectedLeadDetail"
          />

          <LeadDetailResearch
            v-if="selectedLeadDetail.research"
            :lead="selectedLeadDetail"
            :research-enabled="Boolean(settings?.research_enabled)"
            :can-manage="canManage"
            :requesting="researchRequestLeadId === selectedLeadDetail.id"
            :adopting-owner-name="
              adoptingOwner?.leadId === selectedLeadDetail.id
                ? adoptingOwner.name
                : ''
            "
            @research="requestLeadResearch(selectedLeadDetail, $event)"
            @adopt-owner="adoptOwner(selectedLeadDetail, $event)"
          />

          <LeadDetailEnrichment
            v-if="
              selectedLeadDetail.enrichment_status === 'completed' ||
              (!selectedLeadDetail.research &&
                selectedLeadDetail.decision_name) ||
              selectedLeadDetail.enrichment_summary
            "
            :lead="selectedLeadDetail"
          />

          <div class="grid gap-3 sm:grid-cols-2">
            <LeadDetailContact :lead="selectedLeadDetail" />
            <div class="rounded-md border border-n-weak bg-n-solid-2 p-3">
              <div class="text-xs font-medium text-n-slate-10">
                {{ t('PROSPECTING.SEARCH.REPUTATION') }}
              </div>
              <div class="mt-2 text-sm text-n-slate-12">
                {{
                  t('PROSPECTING.SEARCH.RATING_LABEL', {
                    rating: selectedLeadDetail.rating || '-',
                  })
                }}
              </div>
              <div class="text-sm text-n-slate-11">
                {{
                  t('PROSPECTING.SEARCH.REVIEWS_LABEL', {
                    count: selectedLeadDetail.reviews_count || 0,
                  })
                }}
              </div>
            </div>
          </div>

          <LeadDetailReviews
            v-if="leadReviews(selectedLeadDetail).length"
            :lead="selectedLeadDetail"
          />

          <div class="grid gap-3 sm:grid-cols-2">
            <div class="rounded-md border border-n-weak bg-n-solid-2 p-3">
              <div class="text-xs font-medium text-n-slate-10">
                {{ t('PROSPECTING.SEARCH.FIELDS.CATEGORY') }}
              </div>
              <div class="mt-2 text-sm text-n-slate-12">
                {{ selectedLeadDetail.category || '-' }}
              </div>
            </div>
            <div class="rounded-md border border-n-weak bg-n-solid-2 p-3">
              <div class="text-xs font-medium text-n-slate-10">
                {{ t('PROSPECTING.SEARCH.FIELDS.CRM_STAGE') }}
              </div>
              <div class="mt-2 text-sm text-n-slate-12">
                {{ selectedStageName }}
              </div>
            </div>
          </div>

          <div class="rounded-md border border-n-weak bg-n-solid-2 p-3">
            <div class="text-xs font-medium text-n-slate-10">
              {{ t('PROSPECTING.SEARCH.COORDINATES') }}
            </div>
            <div class="mt-2 text-sm text-n-slate-12">
              {{
                selectedLeadDetail.latitude && selectedLeadDetail.longitude
                  ? `${selectedLeadDetail.latitude}, ${selectedLeadDetail.longitude}`
                  : EMPTY_VALUE
              }}
            </div>
          </div>

          <div
            v-if="selectedLeadDetail.discard_reason"
            class="rounded-md border border-n-weak bg-n-solid-2 p-3"
          >
            <div class="text-xs font-medium text-n-slate-10">
              {{ t('PROSPECTING.QUALITY.DISCARD_REASON') }}
            </div>
            <div class="mt-2 text-sm text-n-slate-12">
              {{ selectedLeadDetail.discard_reason }}
            </div>
          </div>
        </section>
      </div>

      <footer class="flex flex-wrap gap-2 border-t border-n-weak px-5 py-4">
        <a
          :href="googleMapsLeadUrl(selectedLeadDetail)"
          target="_blank"
          rel="noopener noreferrer"
          class="inline-flex h-9 items-center gap-2 rounded-md border border-n-weak px-3 text-sm font-medium text-n-slate-12 hover:bg-n-solid-2"
        >
          <span class="i-lucide-map-pin size-4" />
          {{ t('PROSPECTING.SEARCH.OPEN_MAP') }}
        </a>
        <a
          v-if="selectedLeadDetail.contact_id"
          :href="contactUrl(selectedLeadDetail.contact_id)"
          class="inline-flex h-9 items-center rounded-md border border-n-weak px-3 text-sm font-medium text-n-brand underline"
        >
          {{ t('PROSPECTING.SEARCH.OPEN_CONTACT') }}
        </a>
        <a
          v-if="selectedLeadDetail.crm_card_id"
          :href="crmCardUrl(selectedLeadDetail.crm_card_id)"
          class="inline-flex h-9 items-center rounded-md border border-n-weak px-3 text-sm font-medium text-n-brand underline"
        >
          {{ t('PROSPECTING.SEARCH.OPEN_CRM_CARD') }}
        </a>
        <button
          v-else-if="canManage"
          type="button"
          class="h-9 rounded-md bg-n-brand px-3 text-sm font-medium text-white"
          @click="openCrmSend([selectedLeadDetail])"
        >
          {{ t('PROSPECTING.SEARCH.SEND_TO_CRM') }}
        </button>
      </footer>
    </aside>
  </div>
</template>
