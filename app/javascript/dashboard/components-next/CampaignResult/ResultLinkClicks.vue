<script setup>
// "Cliques por link" of an e-mail campaign: the same table the old Gestão de campanhas showed for a
// selected campaign (O1), moved into the e-mail result (#1007). Each web address opens in a new
// tab, shortened to the site and the start of the path (#990).
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import {
  NS,
  formatNumber,
} from 'dashboard/components-next/Campaigns/EmailProtection/presentation';
import { linkLabel } from './linkLabel';

const props = defineProps({
  clicks: { type: Array, default: () => [] },
  loading: Boolean,
  error: Boolean,
});

const { t, locale } = useI18n();
const number = value => formatNumber(value, locale.value);
const rows = computed(() =>
  props.clicks.map(click => ({ ...click, link: linkLabel(click.url) }))
);
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
        v-for="click in rows"
        :key="click.url"
        class="flex min-w-0 flex-col border-b border-n-weak py-2 last:border-0"
        data-link-row
      >
        <a
          v-if="click.link.href"
          :href="click.link.href"
          target="_blank"
          rel="noopener noreferrer"
          :title="click.url"
          :aria-label="
            t('RESULT_JOURNEY.CLICKS.OPEN_ARIA', { url: click.link.href })
          "
          class="flex min-h-11 min-w-0 max-w-full items-center gap-1.5 self-start rounded-lg text-sm font-medium text-n-blue-11 underline-offset-2 hover:underline focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
          data-link
        >
          <bdi dir="ltr" class="min-w-0 truncate">{{ click.link.label }}</bdi>
          <span
            class="i-lucide-external-link size-3.5 shrink-0"
            aria-hidden="true"
          />
        </a>
        <bdi
          v-else
          dir="ltr"
          class="flex min-h-11 min-w-0 items-center truncate text-sm text-n-slate-12"
          :title="click.url"
        >
          {{ click.link.label }}
        </bdi>
        <dl class="m-0 flex flex-wrap gap-x-5 gap-y-1">
          <div class="flex items-baseline gap-1.5">
            <dt class="text-xs text-n-slate-11">
              {{ t('CAMPAIGN_MANAGEMENT.CLICKS_BY_LINK.UNIQUE') }}
            </dt>
            <dd
              class="m-0 text-sm font-semibold tabular-nums text-n-slate-12"
              data-unique
            >
              {{ number(click.unique_clicks) }}
            </dd>
          </div>
          <div class="flex items-baseline gap-1.5">
            <dt class="text-xs text-n-slate-11">
              {{ t('CAMPAIGN_MANAGEMENT.CLICKS_BY_LINK.TOTAL') }}
            </dt>
            <dd
              class="m-0 text-sm font-semibold tabular-nums text-n-slate-12"
              data-total
            >
              {{ number(click.total_clicks) }}
            </dd>
          </div>
        </dl>
      </li>
    </ul>
  </section>
</template>
