<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { formatValueByCurrency } from './trackedLinkWebsite';

// Results per Meta campaign of the selected landing page origin (CA-T.3). Lives
// in the narrow detail aside, so it is a list, not a wide table: the name and
// the won value on top, clicks · conversations · won deals underneath. Every
// number stays visible at any width (no horizontal scroll on phones).
// won_cards and won_value_by_currency are financial: the API only sends them to
// administrators. When they are absent the columns are left out, never shown
// as zero or as a dash (that would read as "no sales").
const props = defineProps({
  campaigns: { type: Array, default: () => [] },
  originName: { type: String, default: '' },
});
const { t, locale } = useI18n();
const NS = 'CRM_KANBAN.TRACKED_LINKS.PAGE';
const language = computed(() => locale.value.replace('_', '-'));
const rows = computed(() =>
  [...props.campaigns].sort(
    (a, b) =>
      (b.conversations || 0) - (a.conversations || 0) ||
      (b.clicks || 0) - (a.clicks || 0)
  )
);
const format = value =>
  new Intl.NumberFormat(language.value).format(Number(value) || 0);
const campaignName = campaign =>
  campaign.campaign_key === 'none' || !campaign.name
    ? t(`${NS}.NO_CAMPAIGN`)
    : campaign.name;
const hasField = (campaign, field) => Object.hasOwn(campaign, field);
const hasWonCards = campaign => hasField(campaign, 'won_cards');
const hasValue = campaign => hasField(campaign, 'won_value_by_currency');
const value = campaign =>
  formatValueByCurrency(campaign.won_value_by_currency, locale.value) || '—';
const stats = campaign => [
  {
    key: 'clicks',
    label: t('CRM_KANBAN.TRACKED_LINKS.CLICKS'),
    value: format(campaign.clicks),
  },
  {
    key: 'conversations',
    label: t('CRM_KANBAN.TRACKED_LINKS.CONVERSATIONS'),
    value: format(campaign.conversations),
    strong: true,
  },
  ...(hasWonCards(campaign)
    ? [{ key: 'won', label: t(`${NS}.WON`), value: format(campaign.won_cards) }]
    : []),
];
</script>

<template>
  <section aria-labelledby="tracked-link-campaigns-title">
    <h3 id="tracked-link-campaigns-title" class="m-0 text-sm font-semibold">
      {{ t(`${NS}.CAMPAIGNS_TITLE`) }}
    </h3>
    <p class="m-0 mt-1 text-xs leading-relaxed text-n-slate-11">
      {{ t(`${NS}.CAMPAIGNS_HINT`, { name: originName }) }}
    </p>
    <ul
      v-if="rows.length"
      class="m-0 mt-3 grid list-none divide-y divide-n-weak rounded-xl border border-n-weak p-0"
    >
      <li
        v-for="campaign in rows"
        :key="campaign.campaign_key"
        data-testid="tracked-link-campaign"
        class="grid gap-3 px-4 py-3"
      >
        <div class="flex min-w-0 items-baseline justify-between gap-3">
          <span
            data-testid="tracked-link-campaign-name"
            class="min-w-0 break-words text-sm font-semibold"
          >
            {{ campaignName(campaign) }}
          </span>
          <span
            v-if="hasValue(campaign)"
            data-testid="tracked-link-campaign-value"
            class="shrink-0 text-sm font-medium tabular-nums"
          >
            <span class="sr-only">{{ t(`${NS}.VALUE`) }}</span>
            {{ value(campaign) }}
          </span>
        </div>
        <dl
          class="m-0 grid gap-2"
          :class="hasWonCards(campaign) ? 'grid-cols-3' : 'grid-cols-2'"
        >
          <div
            v-for="stat in stats(campaign)"
            :key="stat.key"
            :data-testid="`tracked-link-campaign-${stat.key}`"
            class="min-w-0"
          >
            <dt class="truncate text-xs text-n-slate-11">{{ stat.label }}</dt>
            <dd
              class="m-0 text-sm tabular-nums"
              :class="stat.strong ? 'font-semibold text-n-teal-11' : ''"
            >
              {{ stat.value }}
            </dd>
          </div>
        </dl>
      </li>
    </ul>
    <div
      v-else
      class="mt-3 rounded-xl border border-dashed border-n-weak px-5 py-8 text-center"
    >
      <span
        class="i-lucide-megaphone inline-block size-6 text-n-blue-11"
        aria-hidden="true"
      />
      <p class="m-0 mt-2 text-sm font-semibold">
        {{ t(`${NS}.CAMPAIGNS_EMPTY_TITLE`) }}
      </p>
      <p class="m-0 mt-1 text-xs leading-relaxed text-n-slate-11">
        {{ t(`${NS}.CAMPAIGNS_EMPTY_HINT`) }}
      </p>
    </div>
  </section>
</template>
