<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute } from 'vue-router';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import CrmMetaAdsConnectionAPI from 'dashboard/api/crmMetaAdsConnection';
import { conversationUrl, frontendURL } from 'dashboard/helper/URLHelper';
import { intlLocale, relativeTime } from '../metaAdsHelpers';
import { useMetaAdsLive } from '../useMetaAdsLive';
import MetaAdsConfidence from './MetaAdsConfidence.vue';

// Anúncios da Meta (#1088, F3a): o painel do dia a dia do mockup aprovado. Uma frase com o dinheiro, a ação do
// dia com o porquê, o caminho investido → conversas → propostas → vendas, cada anúncio por venda com o veredito
// em palavras e o quanto confiar nos números. Tudo do servidor (Crm::MetaAds::Panel::Report); a tela só
// formata. Fica viva como o resumo (useMetaAdsLive).
const emit = defineEmits(['open']);

const { t, locale } = useI18n();
const route = useRoute();
const PERIODS = [7, 30];
const days = ref(30);
const panel = ref(null);
const loading = ref(true);
const showStalled = ref(false);

const live = useMetaAdsLive({
  // Troca de período no meio de uma leitura: a resposta do período antigo é descartada.
  load: async () => {
    const asked = days.value;
    const { data } = await CrmMetaAdsConnectionAPI.panel(asked);
    if (asked !== days.value) return;
    panel.value = data.panel;
    loading.value = false;
  },
  waiting: () => panel.value?.refreshing,
});

const choosePeriod = value => {
  if (value === days.value) return;
  days.value = value;
  loading.value = true;
  live.reload();
};

const fmt = value =>
  new Intl.NumberFormat(intlLocale(locale.value), {
    style: 'currency',
    currency: panel.value?.currency || 'BRL',
    minimumFractionDigits: Number.isInteger(Number(value)) ? 0 : 2,
    maximumFractionDigits: 2,
  }).format(Number(value || 0));

const totals = computed(() => panel.value?.totals || {});
const updated = computed(() =>
  relativeTime(panel.value?.synced_at, locale.value)
);

// Contagem com singular e plural: "1 venda", "6 vendas".
const counted = (key, n) =>
  t(`CRM_KANBAN.META_ADS_HUB.PANEL.COUNT.${key}`, { n }, n);

const headline = computed(() =>
  t('CRM_KANBAN.META_ADS_HUB.PANEL.HEADLINE', {
    spend: fmt(totals.value.spend),
    conversations: counted('CONVERSATIONS', totals.value.conversations || 0),
    sales: counted('SALES', totals.value.sales || 0),
  })
);

// A ação do dia vem pronta do servidor; aqui só vira frase e porquê.
const action = computed(() => panel.value?.action || { kind: 'wait' });
const actionText = computed(() => {
  const data = action.value;
  const key = `CRM_KANBAN.META_ADS_HUB.PANEL.ACTION.${data.kind.toUpperCase()}`;
  return {
    text: t(
      `${key}.TEXT`,
      {
        count: data.count,
        ad: data.ad_name || t('CRM_KANBAN.META_ADS_HUB.PANEL.SEVERAL_ADS'),
        days: data.days,
        unknown: data.unknown,
      },
      data.count ?? data.unknown ?? 2
    ),
    why: t(`${key}.WHY`, {
      value: fmt(data.value),
      conversations: data.conversations,
      missing: data.missing_conversations,
      ad: data.ad_name || '',
    }),
  };
});

const path = computed(() => [
  { key: 'SPEND', value: fmt(totals.value.spend), plural: 2 },
  {
    key: 'CONVERSATIONS',
    value: totals.value.conversations || 0,
    plural: totals.value.conversations || 0,
    note:
      totals.value.cost_per_conversation != null
        ? t('CRM_KANBAN.META_ADS_HUB.PANEL.EACH', {
            value: fmt(totals.value.cost_per_conversation),
          })
        : null,
  },
  {
    key: 'QUOTES',
    value: totals.value.quotes || 0,
    plural: totals.value.quotes || 0,
    note: totals.value.conversations
      ? t('CRM_KANBAN.META_ADS_HUB.PANEL.REACHED', {
          share: Math.round(
            ((totals.value.quotes || 0) / totals.value.conversations) * 100
          ),
        })
      : null,
  },
  {
    key: 'SALES',
    value: totals.value.sales || 0,
    plural: totals.value.sales || 0,
    win: true,
    extra: totals.value.sales ? fmt(totals.value.sales_value) : null,
    note:
      totals.value.cost_per_sale != null
        ? t('CRM_KANBAN.META_ADS_HUB.PANEL.PER_SALE', {
            value: fmt(totals.value.cost_per_sale),
          })
        : null,
  },
]);

// Sem a imagem do anúncio, cada um ganha uma cor, para não virarem cartões iguais.
const THUMBS = [
  'from-n-blue-9 to-[#0D2344]',
  'from-n-amber-9 to-n-amber-11',
  'from-n-teal-9 to-n-teal-11',
  'from-n-iris-9 to-n-iris-11',
];

const VERDICTS = {
  up: 'bg-n-teal-3 text-n-teal-11',
  keep: 'bg-n-blue-3 text-n-blue-11',
  signal: 'bg-n-amber-3 text-n-amber-11',
  review: 'bg-n-ruby-3 text-n-ruby-11',
  early: 'bg-n-alpha-2 text-n-slate-11',
};

const ads = computed(() => panel.value?.ads || []);
const stalled = computed(() =>
  action.value.kind === 'stalled_quotes' ? action.value.cards || [] : []
);
const stalledMore = computed(
  () => (action.value.count || 0) - stalled.value.length
);

const conversationLink = id =>
  frontendURL(conversationUrl({ accountId: route.params.accountId, id }));

const waitingFor = value => relativeTime(value, locale.value);

const onAction = () => {
  if (action.value.kind === 'stalled_quotes') {
    showStalled.value = !showStalled.value;
  } else if (action.value.kind === 'fix_tracking') {
    emit('open', 3);
  }
};

onMounted(() => live.start());
</script>

<template>
  <section data-meta-ads-panel class="flex flex-col gap-5">
    <div class="flex flex-wrap items-center justify-between gap-3">
      <p class="m-0 text-sm text-n-slate-11">
        {{ $t('CRM_KANBAN.META_ADS_HUB.PANEL.PERIOD_HINT', { days: days }) }}
      </p>
      <div
        role="group"
        :aria-label="$t('CRM_KANBAN.META_ADS_HUB.PANEL.PERIOD_LABEL')"
        class="flex gap-1 p-1 rounded-xl bg-n-alpha-1"
      >
        <button
          v-for="period in PERIODS"
          :key="period"
          type="button"
          :data-panel-period="period"
          :aria-pressed="period === days"
          class="px-4 text-sm font-semibold border-0 rounded-lg min-h-11 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
          :class="
            period === days
              ? 'bg-n-solid-1 text-n-slate-12 shadow-sm'
              : 'bg-transparent text-n-slate-11 hover:text-n-slate-12'
          "
          @click="choosePeriod(period)"
        >
          {{ $t('CRM_KANBAN.META_ADS_HUB.PANEL.PERIOD', { days: period }) }}
        </button>
      </div>
    </div>

    <div v-if="loading && !panel" class="flex justify-center p-12">
      <Spinner />
    </div>

    <template v-else-if="panel">
      <div
        data-panel-hero
        class="relative flex flex-col gap-4 p-5 overflow-hidden text-white rounded-2xl sm:p-7 bg-[#0D2344]"
      >
        <span
          aria-hidden="true"
          class="absolute rounded-full pointer-events-none -end-16 -top-24 size-72 border-[2.5rem] border-n-blue-9 opacity-15"
        />
        <p
          class="relative flex flex-wrap m-0 text-xs text-white/75 gap-x-3 gap-y-1"
          aria-live="polite"
        >
          <span>
            {{ $t('CRM_KANBAN.META_ADS_HUB.PANEL.PERIOD_CTX', { days }) }}
          </span>
          <span v-if="updated">
            {{
              $t('CRM_KANBAN.META_ADS_HUB.SUMMARY.SPEND_UPDATED', {
                time: updated,
              })
            }}
          </span>
          <span
            v-if="panel.refreshing"
            data-panel-refreshing
            class="inline-flex items-center gap-1"
          >
            <span
              class="i-lucide-refresh-cw size-3 animate-spin"
              aria-hidden="true"
            />
            {{ $t('CRM_KANBAN.META_ADS_HUB.SUMMARY.SPEND_REFRESHING') }}
          </span>
        </p>
        <h3
          data-panel-headline
          class="relative m-0 text-2xl font-semibold leading-tight tracking-tight text-white sm:text-3xl text-balance tabular-nums"
        >
          {{ headline }}
        </h3>
        <div
          data-panel-action
          :data-action-kind="action.kind"
          class="relative flex flex-col gap-3 p-4 border border-solid rounded-xl bg-white/10 border-white/15 sm:flex-row sm:items-center"
        >
          <p class="flex-1 m-0 text-sm text-white">
            <strong>{{ $t('CRM_KANBAN.META_ADS_HUB.PANEL.TODAY') }}</strong>
            {{ actionText.text }}
          </p>
          <button
            v-if="action.kind !== 'wait'"
            type="button"
            data-panel-action-button
            class="px-4 text-sm font-semibold bg-white border-0 rounded-xl min-h-11 text-[#0D2344] hover:bg-n-blue-2 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-white"
            @click="onAction"
          >
            {{
              $t(
                `CRM_KANBAN.META_ADS_HUB.PANEL.ACTION.${action.kind.toUpperCase()}.BUTTON`,
                { count: action.count },
                action.count ?? 2
              )
            }}
          </button>
        </div>
        <p class="relative m-0 text-sm text-white/75">
          {{ actionText.why }}
        </p>
      </div>

      <div
        v-if="showStalled && stalled.length"
        data-panel-stalled
        class="flex flex-col gap-2 p-4 border shadow-sm rounded-2xl border-n-weak bg-n-solid-1 sm:p-5"
      >
        <h4 class="m-0 text-base font-semibold text-n-slate-12">
          {{
            $t(
              'CRM_KANBAN.META_ADS_HUB.PANEL.STALLED_TITLE',
              { count: action.count },
              action.count
            )
          }}
        </h4>
        <ul class="flex flex-col gap-2 p-0 m-0 list-none">
          <li
            v-for="card in stalled"
            :key="card.id"
            data-panel-stalled-card
            class="flex flex-wrap items-center gap-3 p-3 border border-solid rounded-xl border-n-weak"
          >
            <span class="flex-1 min-w-0">
              <span
                class="block text-sm font-semibold truncate text-n-slate-12"
              >
                {{ card.title }}
              </span>
              <span class="block text-xs text-n-slate-11">
                {{
                  $t('CRM_KANBAN.META_ADS_HUB.PANEL.STALLED_SINCE', {
                    time: waitingFor(card.waiting_since),
                  })
                }}
              </span>
            </span>
            <span class="text-sm font-semibold tabular-nums text-n-slate-12">
              {{ fmt(card.value) }}
            </span>
            <router-link
              v-if="card.conversation_id"
              :to="conversationLink(card.conversation_id)"
              class="inline-flex items-center px-3 text-sm font-medium no-underline border border-solid rounded-lg min-h-11 border-n-weak text-n-slate-12 hover:bg-n-alpha-1"
            >
              {{ $t('CRM_KANBAN.META_ADS_HUB.PANEL.OPEN_CONVERSATION') }}
            </router-link>
          </li>
        </ul>
        <p
          v-if="stalledMore > 0"
          data-panel-stalled-more
          class="m-0 text-sm text-n-slate-11"
        >
          {{
            $t('CRM_KANBAN.META_ADS_HUB.PANEL.STALLED_MORE', {
              count: stalledMore,
            })
          }}
        </p>
      </div>

      <div
        class="flex flex-col gap-3 p-4 border shadow-sm rounded-2xl border-n-weak bg-n-solid-1 sm:p-5"
      >
        <h4 class="m-0 text-base font-semibold text-n-slate-12">
          {{ $t('CRM_KANBAN.META_ADS_HUB.PANEL.PATH_TITLE') }}
        </h4>
        <ol class="grid grid-cols-2 gap-2 p-0 m-0 list-none lg:grid-cols-4">
          <li
            v-for="step in path"
            :key="step.key"
            :data-panel-path="step.key"
            class="flex flex-col gap-0.5 p-3 rounded-xl"
            :class="step.win ? 'bg-n-teal-3' : 'bg-n-alpha-1'"
          >
            <span
              class="text-xl font-semibold tabular-nums"
              :class="step.win ? 'text-n-teal-11' : 'text-n-slate-12'"
            >
              {{ step.value }}
            </span>
            <span class="text-xs text-n-slate-11">
              {{
                $t(
                  `CRM_KANBAN.META_ADS_HUB.PANEL.PATH.${step.key}`,
                  step.plural
                )
              }}
              <template v-if="step.extra">
                {{
                  $t('CRM_KANBAN.META_ADS_HUB.PANEL.SALES_VALUE', {
                    value: step.extra,
                  })
                }}
              </template>
            </span>
            <span v-if="step.note" class="text-xs text-n-slate-11">
              {{ step.note }}
            </span>
          </li>
        </ol>
        <ul class="flex flex-wrap gap-2 p-0 m-0 list-none tabular-nums">
          <li
            v-if="totals.return_per_real != null"
            class="px-3 py-1.5 text-sm border border-solid rounded-full border-n-weak text-n-slate-12"
          >
            {{
              $t('CRM_KANBAN.META_ADS_HUB.PANEL.RETURN', {
                value: fmt(totals.return_per_real),
              })
            }}
          </li>
          <li
            class="px-3 py-1.5 text-sm border border-solid rounded-full border-n-weak text-n-slate-12"
          >
            {{
              $t(
                'CRM_KANBAN.META_ADS_HUB.PANEL.OPEN_QUOTES',
                { count: totals.open_quotes || 0 },
                totals.open_quotes || 0
              )
            }}
          </li>
        </ul>
      </div>

      <div
        class="flex flex-col gap-3 p-4 border shadow-sm rounded-2xl border-n-weak bg-n-solid-1 sm:p-5"
      >
        <h4 class="m-0 text-base font-semibold text-n-slate-12">
          {{ $t('CRM_KANBAN.META_ADS_HUB.PANEL.ADS_TITLE') }}
        </h4>
        <p v-if="!ads.length" class="m-0 text-sm text-n-slate-11">
          {{ $t('CRM_KANBAN.META_ADS_HUB.PANEL.ADS_EMPTY') }}
        </p>
        <ul
          v-else
          class="grid gap-3 p-0 m-0 list-none sm:grid-cols-2 xl:grid-cols-3"
        >
          <li
            v-for="(ad, index) in ads"
            :key="ad.ad_id"
            :data-panel-ad="ad.ad_id"
            class="flex flex-col overflow-hidden border border-solid rounded-xl border-n-weak"
          >
            <div
              class="relative flex items-end h-24 p-3 bg-gradient-to-br"
              :class="THUMBS[index % THUMBS.length]"
            >
              <img
                v-if="ad.thumbnail_url"
                :src="ad.thumbnail_url"
                alt=""
                loading="lazy"
                class="absolute inset-0 object-cover size-full"
              />
              <span
                class="relative text-sm font-semibold text-white truncate drop-shadow"
              >
                {{ ad.name || $t('CRM_KANBAN.META_ADS_HUB.PANEL.AD_NO_NAME') }}
              </span>
            </div>
            <div class="flex flex-col gap-1.5 p-3">
              <span
                :data-verdict="ad.verdict"
                class="px-2.5 py-0.5 text-xs font-semibold rounded-full w-fit"
                :class="VERDICTS[ad.verdict]"
              >
                {{
                  $t(
                    `CRM_KANBAN.META_ADS_HUB.PANEL.VERDICT.${ad.verdict.toUpperCase()}`
                  )
                }}
              </span>
              <span class="text-sm tabular-nums text-n-slate-12">
                {{
                  $t('CRM_KANBAN.META_ADS_HUB.PANEL.AD_LINE', {
                    spend: fmt(ad.spend),
                    conversations: counted('CONVERSATIONS', ad.conversations),
                    sales: counted('SALES', ad.sales),
                  })
                }}
              </span>
              <span class="text-xs tabular-nums text-n-slate-11">
                {{
                  ad.cost_per_sale != null
                    ? $t('CRM_KANBAN.META_ADS_HUB.PANEL.PER_SALE', {
                        value: fmt(ad.cost_per_sale),
                      })
                    : $t(
                        'CRM_KANBAN.META_ADS_HUB.PANEL.AD_QUOTES',
                        { count: ad.quotes },
                        ad.quotes
                      )
                }}
              </span>
            </div>
          </li>
        </ul>
      </div>

      <MetaAdsConfidence
        v-if="panel.confidence"
        :confidence="panel.confidence"
        @fix="emit('open', 3)"
      />
    </template>
  </section>
</template>
