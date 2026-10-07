<script setup>
import { computed, nextTick, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import CrmMetaAdsConnectionAPI from 'dashboard/api/crmMetaAdsConnection';
import { conversationUrl, frontendURL } from 'dashboard/helper/URLHelper';
import {
  VERDICT_CLASSES,
  amount,
  relativeTime,
  thumbClass,
} from '../metaAdsHelpers';
import { useMetaAdsLive } from '../useMetaAdsLive';
import MetaAdsConfidence from './MetaAdsConfidence.vue';
import MetaAdsAdDetail from './MetaAdsAdDetail.vue';
import MetaAdsDailyAction from './MetaAdsDailyAction.vue';
import MetaAdsQuoteMessage from './MetaAdsQuoteMessage.vue';

// Anúncios da Meta (#1088, F3a): o painel do dia a dia do mockup aprovado. Uma frase com o dinheiro, a ação do
// dia com o porquê, o caminho investido → conversas → propostas → vendas, cada anúncio por venda com o veredito
// em palavras e o quanto confiar nos números. Tudo do servidor (Crm::MetaAds::Panel::Report); a tela só
// formata. Fica viva como o resumo (useMetaAdsLive).
const emit = defineEmits(['open']);

const { t, locale } = useI18n();
const route = useRoute();
const router = useRouter();
const PERIODS = [7, 30];
const days = ref(30);
const panel = ref(null);
const loading = ref(true);
const showStalled = ref(false);
// Anúncio aberto por dentro (F3b), lembrado no endereço (?anuncio=) como a aba da página: recarregar ou
// mandar o link abre o mesmo anúncio. Com ele aberto, o detalhe ocupa o lugar do painel; o período continua
// valendo para os dois. O endereço é a única fonte: o menu lateral que volta para a mesma página sem a query
// também fecha o anúncio.
const anuncioFromRoute = () =>
  route.query.anuncio ? String(route.query.anuncio) : null;
const openAd = ref(anuncioFromRoute());
const rememberAd = value => {
  const query = { ...route.query };
  if (value) query.anuncio = value;
  else delete query.anuncio;
  router.replace({ query });
};

// Ao voltar do anúncio, o foco e a rolagem voltam ao cartão dele: quem compara anúncios um a um pelo teclado
// não recomeça do topo da página.
const focusCard = adId =>
  nextTick(() =>
    document.querySelector(`[data-panel-ad-open="${adId}"]`)?.focus()
  );

watch(anuncioFromRoute, value => {
  const closed = openAd.value;
  openAd.value = value;
  if (!value && closed) focusCard(closed);
});

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

const fmt = value => amount(value, panel.value?.currency, locale.value);

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

const ads = computed(() => panel.value?.ads || []);
// O link de imagem da Meta vence (o "oe=" da URL); imagem que não abre vira o quadro de reserva. Guarda o link
// que falhou por anúncio: quando a renovação diária traz um link novo, a imagem volta sem recarregar a página.
const brokenImages = ref({});
// Os três números de cada anúncio: o investido numa linha, conversas e vendas lado a lado embaixo (em três
// colunas o rótulo "Conversas" não cabe no cartão estreito).
const adStats = ad => [
  { key: 'SPEND', value: fmt(ad.spend) },
  { key: 'CONVERSATIONS', value: ad.conversations },
  { key: 'SALES', value: ad.sales },
];
const stalled = computed(() =>
  action.value.kind === 'stalled_quotes' ? action.value.cards || [] : []
);
const stalledMore = computed(
  () => (action.value.count || 0) - stalled.value.length
);

const conversationLink = id =>
  frontendURL(conversationUrl({ accountId: route.params.accountId, id }));

const waitingFor = value => relativeTime(value, locale.value);

// O botão da ação do dia (pela regra ou pela IA, F4a): a IA pode apontar um anúncio para revisar.
const onAction = ({ kind, adId }) => {
  if (kind === 'stalled_quotes') {
    showStalled.value = !showStalled.value;
  } else if (kind === 'fix_tracking') {
    emit('open', 3);
  } else if (kind === 'review_ad' && adId) {
    rememberAd(String(adId));
  }
};

onMounted(() => live.start());
</script>

<template>
  <section data-meta-ads-panel class="flex flex-col gap-5">
    <div class="flex flex-wrap items-center justify-between gap-3">
      <p class="m-0 text-sm font-420 text-n-slate-11">
        {{ $t('CRM_KANBAN.META_ADS_HUB.PANEL.PERIOD_HINT', { days: days }) }}
      </p>
      <div
        role="group"
        :aria-label="$t('CRM_KANBAN.META_ADS_HUB.PANEL.PERIOD_LABEL')"
        class="flex gap-1 p-1 rounded-lg bg-n-alpha-1"
      >
        <button
          v-for="period in PERIODS"
          :key="period"
          type="button"
          :data-panel-period="period"
          :aria-pressed="period === days"
          class="px-4 text-[13px] font-520 border-0 rounded-md min-h-11 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
          :class="
            period === days
              ? 'bg-n-solid-1 text-n-slate-12 shadow-[0_1px_2px_rgba(0,0,0,0.06)]'
              : 'bg-transparent text-n-slate-11 hover:text-n-slate-12'
          "
          @click="choosePeriod(period)"
        >
          {{ $t('CRM_KANBAN.META_ADS_HUB.PANEL.PERIOD', { days: period }) }}
        </button>
      </div>
    </div>

    <MetaAdsAdDetail
      v-if="openAd"
      :key="openAd"
      :ad-id="openAd"
      :days="days"
      @back="rememberAd(null)"
    />

    <div v-else-if="loading && !panel" class="flex justify-center p-12">
      <Spinner />
    </div>

    <template v-else-if="panel">
      <div
        data-panel-hero
        class="relative flex flex-col gap-5 p-6 overflow-hidden text-white rounded-xl sm:p-8 bg-[#0D2344]"
      >
        <span
          aria-hidden="true"
          class="absolute rounded-full pointer-events-none -end-16 -top-24 size-72 border-[2.5rem] border-n-blue-9 opacity-10"
        />
        <p
          class="relative flex flex-wrap m-0 text-[13px] font-420 text-white/65 gap-x-3 gap-y-1"
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
          class="relative max-w-3xl m-0 font-interDisplay text-[28px] sm:text-[36px] font-520 leading-[1.12] tracking-[-0.02em] text-white text-balance tabular-nums"
        >
          {{ headline }}
        </h3>
        <MetaAdsDailyAction
          :action="action"
          :rule-text="actionText"
          :days="days"
          @act="onAction"
        />
      </div>

      <!-- v-show: fechar a lista não apaga o que cada mensagem sugerida já fez (rascunho, "Enviada"). -->
      <div
        v-if="stalled.length"
        v-show="showStalled"
        data-panel-stalled
        class="flex flex-col gap-4 p-5 border border-solid rounded-xl border-n-weak bg-n-solid-1 sm:p-6"
      >
        <h4
          class="m-0 text-xs font-520 uppercase tracking-[0.08em] text-n-slate-11"
        >
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
            class="flex flex-wrap items-center gap-4 px-4 py-3 border border-solid rounded-lg border-n-weak"
          >
            <span class="flex-1 min-w-0">
              <span class="block text-sm font-520 truncate text-n-slate-12">
                {{ card.title }}
              </span>
              <span class="block text-xs font-420 text-n-slate-10">
                {{
                  $t('CRM_KANBAN.META_ADS_HUB.PANEL.STALLED_SINCE', {
                    time: waitingFor(card.waiting_since),
                  })
                }}
              </span>
            </span>
            <span
              class="font-interDisplay text-base font-520 tabular-nums text-n-slate-12"
            >
              {{ fmt(card.value) }}
            </span>
            <router-link
              v-if="card.conversation_id"
              :to="conversationLink(card.conversation_id)"
              class="inline-flex items-center px-3 text-[13px] font-460 no-underline border border-solid rounded-lg min-h-11 border-n-weak text-n-slate-12 hover:bg-n-alpha-1"
            >
              {{ $t('CRM_KANBAN.META_ADS_HUB.PANEL.OPEN_CONVERSATION') }}
            </router-link>
            <MetaAdsQuoteMessage v-if="card.conversation_id" :card="card" />
          </li>
        </ul>
        <p
          v-if="stalledMore > 0"
          data-panel-stalled-more
          class="m-0 text-[13px] font-420 text-n-slate-11"
        >
          {{
            $t('CRM_KANBAN.META_ADS_HUB.PANEL.STALLED_MORE', {
              count: stalledMore,
            })
          }}
        </p>
      </div>

      <div
        class="flex flex-col gap-5 p-5 border border-solid rounded-xl border-n-weak bg-n-solid-1 sm:p-6"
      >
        <h4
          class="m-0 text-xs font-520 uppercase tracking-[0.08em] text-n-slate-11"
        >
          {{ $t('CRM_KANBAN.META_ADS_HUB.PANEL.PATH_TITLE') }}
        </h4>
        <ol
          class="grid grid-cols-2 p-0 m-0 list-none gap-y-6 gap-x-4 xl:grid-cols-4 xl:gap-x-0"
        >
          <li
            v-for="step in path"
            :key="step.key"
            :data-panel-path="step.key"
            class="flex flex-col gap-1.5 xl:px-6 xl:first:ps-0 xl:[&:not(:first-child)]:border-0 xl:[&:not(:first-child)]:border-s xl:[&:not(:first-child)]:border-solid xl:[&:not(:first-child)]:border-n-weak"
          >
            <span
              class="font-interDisplay text-[30px] font-520 leading-none tracking-[-0.02em] tabular-nums"
              :class="step.win ? 'text-n-teal-11' : 'text-n-slate-12'"
            >
              {{ step.value }}
            </span>
            <span class="text-[13px] font-440 text-n-slate-11">
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
            <span v-if="step.note" class="text-xs font-420 text-n-slate-10">
              {{ step.note }}
            </span>
          </li>
        </ol>
        <ul class="flex flex-wrap gap-2 p-0 m-0 list-none tabular-nums">
          <li
            v-if="totals.return_per_real != null"
            class="px-2.5 py-1 text-[13px] font-440 rounded-md bg-n-alpha-1 text-n-slate-12"
          >
            {{
              $t('CRM_KANBAN.META_ADS_HUB.PANEL.RETURN', {
                value: fmt(totals.return_per_real),
              })
            }}
          </li>
          <li
            class="px-2.5 py-1 text-[13px] font-440 rounded-md bg-n-alpha-1 text-n-slate-12"
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
        class="flex flex-col gap-5 p-5 border border-solid rounded-xl border-n-weak bg-n-solid-1 sm:p-6"
      >
        <h4
          class="m-0 text-xs font-520 uppercase tracking-[0.08em] text-n-slate-11"
        >
          {{ $t('CRM_KANBAN.META_ADS_HUB.PANEL.ADS_TITLE') }}
        </h4>
        <p v-if="!ads.length" class="m-0 text-sm text-n-slate-11">
          {{ $t('CRM_KANBAN.META_ADS_HUB.PANEL.ADS_EMPTY') }}
        </p>
        <ul
          v-else
          class="grid items-start gap-5 p-0 m-0 list-none sm:grid-cols-2 xl:grid-cols-3"
        >
          <li
            v-for="ad in ads"
            :key="ad.ad_id"
            :data-panel-ad="ad.ad_id"
            class="relative flex flex-col overflow-hidden border border-solid rounded-lg border-n-weak bg-n-solid-1 hover:border-n-strong has-[:focus-visible]:ring-2 has-[:focus-visible]:ring-n-brand"
          >
            <div class="flex justify-center bg-n-alpha-1">
              <img
                v-if="
                  ad.thumbnail_url &&
                  brokenImages[ad.ad_id] !== ad.thumbnail_url
                "
                :src="ad.thumbnail_url"
                :alt="ad.name || ''"
                loading="lazy"
                data-panel-ad-image
                class="block object-contain w-full h-auto max-h-[32rem]"
                @error="brokenImages[ad.ad_id] = ad.thumbnail_url"
              />
              <div
                v-else
                data-panel-ad-placeholder
                class="grid w-full aspect-square place-items-center bg-gradient-to-br"
                :class="thumbClass(ad.ad_id)"
              >
                <span
                  class="i-lucide-image size-8 text-white/50"
                  aria-hidden="true"
                />
              </div>
            </div>
            <div class="flex flex-col gap-4 p-4">
              <div class="flex items-start justify-between gap-3">
                <span
                  class="text-sm font-520 leading-snug text-n-slate-12 line-clamp-2"
                >
                  {{
                    ad.name || $t('CRM_KANBAN.META_ADS_HUB.PANEL.AD_NO_NAME')
                  }}
                </span>
                <span
                  :data-verdict="ad.verdict"
                  class="flex-none px-2 py-0.5 text-[11px] font-520 uppercase tracking-[0.06em] rounded whitespace-nowrap"
                  :class="VERDICT_CLASSES[ad.verdict]"
                >
                  {{
                    $t(
                      `CRM_KANBAN.META_ADS_HUB.PANEL.VERDICT.${ad.verdict.toUpperCase()}`
                    )
                  }}
                </span>
              </div>
              <dl class="grid grid-cols-2 m-0 gap-x-3 gap-y-3">
                <div
                  v-for="stat in adStats(ad)"
                  :key="stat.key"
                  class="flex flex-col gap-1 min-w-0"
                  :class="{ 'col-span-2': stat.key === 'SPEND' }"
                >
                  <dt class="text-xs font-440 text-n-slate-10">
                    {{
                      $t(`CRM_KANBAN.META_ADS_HUB.PANEL.AD_STATS.${stat.key}`)
                    }}
                  </dt>
                  <dd
                    class="m-0 text-base whitespace-nowrap font-interDisplay font-520 tabular-nums text-n-slate-12"
                  >
                    {{ stat.value }}
                  </dd>
                </div>
              </dl>
              <p class="m-0 text-xs font-420 tabular-nums text-n-slate-10">
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
              </p>
              <!-- O botão cobre o cartão inteiro (after:inset-0): tocar em qualquer parte abre o anúncio, e o
                   leitor de tela ouve um só botão com o nome dele. -->
              <button
                type="button"
                :data-panel-ad-open="ad.ad_id"
                :aria-label="
                  $t('CRM_KANBAN.META_ADS_HUB.PANEL.OPEN_AD_LABEL', {
                    name:
                      ad.name || $t('CRM_KANBAN.META_ADS_HUB.PANEL.AD_NO_NAME'),
                  })
                "
                class="inline-flex items-center self-start gap-1 p-0 text-[13px] font-440 bg-transparent border-0 min-h-11 text-n-blue-11 focus-visible:outline-none after:absolute after:inset-0 after:content-['']"
                @click="rememberAd(String(ad.ad_id))"
              >
                {{ $t('CRM_KANBAN.META_ADS_HUB.PANEL.OPEN_AD') }}
                <span
                  class="i-lucide-arrow-right size-3.5"
                  aria-hidden="true"
                />
              </button>
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
