<script setup>
import { useI18n } from 'vue-i18n';
import SearchSummaryLocation from './SearchSummaryLocation.vue';
import { useProspectingSearchContext } from '../../composables/useProspectingSearch';

const { t } = useI18n();
const { form, summaryRadiusKm } = useProspectingSearchContext();
</script>

<template>
  <aside
    class="grid content-start gap-3 rounded-md border border-n-weak bg-n-solid-2 p-4"
  >
    <div>
      <h2 class="text-sm font-semibold text-n-slate-12">
        {{ t('PROSPECTING.SEARCH.SECTIONS.RUN') }}
      </h2>
      <p class="mt-1 text-xs text-n-slate-10">
        {{ t('PROSPECTING.SEARCH.SEARCH_SUMMARY_HINT') }}
      </p>
    </div>
    <dl class="grid gap-3 text-sm text-n-slate-11">
      <div class="grid gap-1">
        <dt class="text-xs text-n-slate-10">
          {{ t('PROSPECTING.SEARCH.FIELDS.QUERY') }}
        </dt>
        <dd class="break-words font-medium text-n-slate-12">
          {{ form.query || '-' }}
        </dd>
      </div>
      <SearchSummaryLocation />
      <div class="grid grid-cols-2 gap-3">
        <div>
          <dt class="text-xs text-n-slate-10">
            {{ t('PROSPECTING.SEARCH.FIELDS.RADIUS_KM') }}
          </dt>
          <dd class="font-medium text-n-slate-12">
            {{ summaryRadiusKm ?? '-' }}
          </dd>
        </div>
        <div>
          <dt class="text-xs text-n-slate-10">
            {{ t('PROSPECTING.SEARCH.FIELDS.LIMIT') }}
          </dt>
          <dd class="font-medium text-n-slate-12">
            {{ form.requested_limit }}
          </dd>
        </div>
      </div>
    </dl>
  </aside>
</template>
