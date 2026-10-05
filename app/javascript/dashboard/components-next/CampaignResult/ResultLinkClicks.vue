<script setup>
// "Cliques por link" of an e-mail campaign: the same table the old Gestão de campanhas showed for a
// selected campaign (O1), moved into the e-mail result (#1007).
import { useI18n } from 'vue-i18n';
import {
  NS,
  formatNumber,
} from 'dashboard/components-next/Campaigns/EmailProtection/presentation';

defineProps({
  clicks: { type: Array, default: () => [] },
  loading: Boolean,
  error: Boolean,
});

const { t, locale } = useI18n();
const number = value => formatNumber(value, locale.value);
</script>

<template>
  <section
    class="flex min-w-0 flex-col gap-3 rounded-2xl border border-n-weak bg-n-solid-1 p-5 shadow-sm"
    data-link-clicks
  >
    <h2 class="mb-0 text-base font-semibold text-n-slate-12">
      {{ t('CAMPAIGN_MANAGEMENT.CLICKS_BY_LINK.TITLE') }}
    </h2>
    <p v-if="loading" class="m-0 text-sm text-n-slate-11">
      {{ t(`${NS}.LOADING`) }}
    </p>
    <p v-else-if="error" role="alert" class="m-0 text-sm text-n-ruby-11">
      {{ t(`${NS}.ERROR`) }}
    </p>
    <p v-else-if="!clicks.length" class="m-0 text-sm text-n-slate-11">
      {{ t('CAMPAIGN_MANAGEMENT.CLICKS_BY_LINK.EMPTY') }}
    </p>
    <ul v-else class="m-0 flex list-none flex-col p-0">
      <li
        v-for="click in clicks"
        :key="click.url"
        class="flex flex-col gap-1 border-b border-n-weak py-2 last:border-0"
      >
        <bdi dir="ltr" class="break-all text-sm text-n-slate-12">
          {{ click.url }}
        </bdi>
        <span class="text-xs text-n-slate-11">
          {{ t('CAMPAIGN_MANAGEMENT.CLICKS_BY_LINK.UNIQUE') }}
          {{ number(click.unique_clicks) }} ·
          {{ t('CAMPAIGN_MANAGEMENT.CLICKS_BY_LINK.TOTAL') }}
          {{ number(click.total_clicks) }}
        </span>
      </li>
    </ul>
  </section>
</template>
