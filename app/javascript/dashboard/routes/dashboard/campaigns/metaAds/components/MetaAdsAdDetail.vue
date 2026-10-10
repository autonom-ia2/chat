<script setup>
import { computed, nextTick, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute } from 'vue-router';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import CrmMetaAdsConnectionAPI from 'dashboard/api/crmMetaAdsConnection';
import { conversationUrl, frontendURL } from 'dashboard/helper/URLHelper';
import {
  VERDICT_CLASSES,
  amount,
  intlLocale,
  relativeTime,
  thumbClass,
} from '../metaAdsHelpers';
import { useMetaAdsLive } from '../useMetaAdsLive';

// Anúncios da Meta (#1088, F3b): o anúncio por dentro, passos 3 e 4 da jornada "O painel do dia a dia". A
// imagem no formato dela, o veredito com o porquê em números, o custo por venda ao lado da média da conta, o
// gasto e as conversas de cada dia e as propostas que vieram dele. Os números e o veredito vêm prontos do
// servidor (GET panel_ad, só banco); a tela só formata. Fica viva como o painel (useMetaAdsLive).
const props = defineProps({
  adId: { type: String, required: true },
  days: { type: Number, required: true },
});

const emit = defineEmits(['back']);

const { t, locale } = useI18n();
const route = useRoute();
const ad = ref(null);
const loading = ref(true);
const failed = ref(false);
const heading = ref(null);
const quotesHeading = ref(null);
let focused = false;

const isCurrent = asked =>
  asked.adId === props.adId && asked.days === props.days;

const live = useMetaAdsLive({
  // Trocar de anúncio ou de período no meio de uma leitura: a resposta antiga é descartada.
  load: async () => {
    const asked = { adId: props.adId, days: props.days };
    let data;
    try {
      ({ data } = await CrmMetaAdsConnectionAPI.panelAd(
        asked.adId,
        asked.days
      ));
    } catch (error) {
      // Sem nenhum número na tela, a falha vira aviso com "tentar de novo" em vez de spinner sem fim; com
      // números, eles ficam. O erro segue para o useMetaAdsLive, que agenda a próxima tentativa.
      if (isCurrent(asked)) {
        failed.value = true;
        loading.value = false;
      }
      throw error;
    }
    if (!isCurrent(asked)) return;
    ad.value = data.ad;
    failed.value = false;
    loading.value = false;
    // Quem abriu o anúncio pelo teclado ou leitor de tela cai no título dele, não no topo da página.
    if (focused) return;
    focused = true;
    nextTick(() => heading.value?.focus());
  },
});

const retry = () => {
  loading.value = true;
  failed.value = false;
  live.reload();
};

watch(() => [props.adId, props.days], retry);

const fmt = value => amount(value, ad.value?.currency, locale.value);

// Sem venda ainda, o custo por venda não existe; um traço é mais honesto que R$ 0.
const money = value =>
  value == null ? t('CRM_KANBAN.META_ADS_HUB.AD_DETAIL.NO_VALUE') : fmt(value);

// Campanha e conjunto com o rótulo à parte do nome: os nomes padrão da Meta já começam com "Campanha" ou
// "Conjunto", e o rótulo na mesma frase repetiria a palavra.
const context = computed(() =>
  [
    { key: 'CAMPAIGN', name: ad.value?.campaign_name },
    { key: 'ADSET', name: ad.value?.adset_name },
  ].filter(part => part.name)
);

const reason = computed(() => ad.value?.reason || { kind: 'early' });

// O custo por venda fica verde abaixo da média e vermelho acima: é a comparação que decide o veredito.
const COST_TONES = {
  below_average: 'text-n-teal-11',
  above_average: 'text-n-ruby-11',
};

const makeTile = (key, value, tone = 'text-n-slate-12') => ({
  key,
  value,
  tone,
});

// Com venda, o custo por venda ao lado da média da conta é a comparação que decide o veredito. Sem venda não
// há custo por venda: em vez de dois traços no topo, os números que existem (investido, conversas, propostas).
const tiles = computed(() => {
  const data = ad.value;
  const conversations = makeTile('CONVERSATIONS', data.conversations || 0);
  if (data.cost_per_sale == null) {
    return [
      makeTile('SPEND', fmt(data.spend)),
      conversations,
      makeTile('QUOTES', data.quotes || 0),
      makeTile('SALES', data.sales || 0),
    ];
  }
  return [
    makeTile(
      'COST_PER_SALE',
      money(data.cost_per_sale),
      COST_TONES[reason.value.kind]
    ),
    makeTile('AVERAGE', money(data.account_average_cost_per_sale)),
    makeTile('SALES', data.sales || 0),
    conversations,
  ];
});

// A frase do porquê muda com o motivo; o plural segue o número que a frase conta (conversas ou vendas).
const REASON_COUNTS = {
  early: 'conversations',
  no_sales: 'conversations',
};

const reasonText = computed(() => {
  const data = reason.value;
  const count = ad.value[REASON_COUNTS[data.kind] || 'sales'] || 0;
  return t(
    `CRM_KANBAN.META_ADS_HUB.AD_DETAIL.REASON.${data.kind.toUpperCase()}`,
    {
      count,
      missing: data.missing_conversations,
      spend: fmt(ad.value.spend),
      cost: money(ad.value.cost_per_sale),
      average: money(ad.value.account_average_cost_per_sale),
      difference: fmt(data.difference),
    },
    count
  );
});

const quotes = computed(() => ad.value?.quotes_list || []);
// Das propostas do anúncio (que incluem as vendidas), as abertas. Vem dos números do anúncio, não da lista,
// que o servidor corta em 20.
const openQuotes = computed(() =>
  Math.max((ad.value?.quotes || 0) - (ad.value?.sales || 0), 0)
);

// "Ver" do Enquanto isso: leva à lista de propostas, com o foco no título dela.
const showQuotes = () => {
  quotesHeading.value?.scrollIntoView({ block: 'start', behavior: 'smooth' });
  quotesHeading.value?.focus({ preventScroll: true });
};

const conversationLink = id =>
  frontendURL(conversationUrl({ accountId: route.params.accountId, id }));

const waitingFor = value => relativeTime(value, locale.value);

// Gráfico do período: uma barra de gasto por dia e um ponto por dia com conversa. Cada série tem a própria
// escala (dinheiro e pessoas não se comparam na mesma régua); o que importa é ver os dias juntos. O desenho
// estica para a altura fixa da caixa (no celular ele não encolhe até sumir) e o ponto é um traço de largura
// zero com ponta redonda e espessura fixa na tela, que continua redondo quando o desenho estica.
const CHART = { width: 600, height: 160, top: 12 };

const dayLabel = date =>
  new Date(`${date}T00:00:00Z`).toLocaleDateString(intlLocale(locale.value), {
    day: '2-digit',
    month: 'short',
    timeZone: 'UTC',
  });

const chart = computed(() => {
  const daily = ad.value?.daily || [];
  const slot = CHART.width / Math.max(daily.length, 1);
  const room = CHART.height - CHART.top;
  const maxSpend = Math.max(...daily.map(day => Number(day.spend) || 0), 0);
  const maxTalks = Math.max(...daily.map(day => day.conversations || 0), 0);

  const days = daily.map((day, index) => {
    const spend = Number(day.spend) || 0;
    const height = maxSpend ? (spend / maxSpend) * room : 0;
    const talks = day.conversations || 0;
    return {
      date: day.date,
      label: dayLabel(day.date),
      spend: fmt(spend),
      talks,
      x: index * slot + slot * 0.2,
      width: Math.max(slot * 0.6, 1),
      y: CHART.height - height,
      height,
      center: index * slot + slot / 2,
      dot: talks ? CHART.height - (talks / maxTalks) * room : null,
      title: t(
        'CRM_KANBAN.META_ADS_HUB.AD_DETAIL.CHART_DAY',
        { date: dayLabel(day.date), spend: fmt(spend), count: talks },
        talks
      ),
    };
  });
  return { days, maxSpend: fmt(maxSpend), maxTalks };
});

// Três datas no eixo bastam: começo, meio e fim do período.
const axis = computed(() => {
  const daily = ad.value?.daily || [];
  if (!daily.length) return [];
  const picks = [0, Math.floor((daily.length - 1) / 2), daily.length - 1];
  return [...new Set(picks)].map(index => dayLabel(daily[index].date));
});

onMounted(() => live.start());

// Link de imagem da Meta vencido: mostra o quadro de reserva (guarda a URL que falhou, então um link novo volta
// a tentar).
const brokenImage = ref(null);
</script>

<template>
  <section data-ad-detail class="flex flex-col gap-5">
    <button
      type="button"
      data-ad-detail-back
      class="inline-flex items-center self-start gap-2 px-3 text-sm font-440 bg-transparent border border-solid rounded-lg min-h-11 border-n-weak text-n-slate-12 hover:bg-n-alpha-1 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
      @click="emit('back')"
    >
      <span class="i-lucide-arrow-left size-4" aria-hidden="true" />
      {{ $t('CRM_KANBAN.META_ADS_HUB.AD_DETAIL.BACK') }}
    </button>

    <div v-if="loading && !ad" class="flex justify-center p-12">
      <Spinner />
    </div>

    <div
      v-else-if="failed && !ad"
      data-ad-detail-error
      role="alert"
      class="flex flex-wrap items-center justify-between gap-3 p-6 border border-solid rounded-xl border-n-weak bg-n-solid-1"
    >
      <p class="m-0 text-sm font-420 text-n-slate-11">
        {{ $t('CRM_KANBAN.META_ADS_HUB.AD_DETAIL.ERROR') }}
      </p>
      <button
        type="button"
        data-ad-detail-retry
        class="inline-flex items-center px-3 text-[13px] font-440 bg-transparent border border-solid rounded-lg min-h-11 border-n-weak text-n-slate-12 hover:bg-n-alpha-1 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
        @click="retry"
      >
        {{ $t('CRM_KANBAN.META_ADS_HUB.AD_DETAIL.RETRY') }}
      </button>
    </div>

    <p
      v-else-if="!ad"
      data-ad-detail-empty
      class="p-6 m-0 text-sm font-420 border border-solid rounded-xl border-n-weak bg-n-solid-1 text-n-slate-11"
    >
      {{ $t('CRM_KANBAN.META_ADS_HUB.AD_DETAIL.EMPTY') }}
    </p>

    <template v-else>
      <header class="flex flex-col gap-1.5">
        <p class="m-0 text-[13px] font-420 text-n-slate-11">
          {{ $t('CRM_KANBAN.META_ADS_HUB.PANEL.PERIOD_CTX', { days }) }}
        </p>
        <h3
          ref="heading"
          tabindex="-1"
          data-ad-detail-name
          class="m-0 font-interDisplay text-[28px] font-520 leading-[1.15] tracking-[-0.02em] text-n-slate-12 text-balance focus:outline-none"
        >
          {{ ad.name || $t('CRM_KANBAN.META_ADS_HUB.PANEL.AD_NO_NAME') }}
        </h3>
        <p
          v-if="context.length"
          data-ad-detail-context
          class="flex flex-wrap items-baseline m-0 text-sm font-420 gap-x-5 gap-y-1 text-n-slate-11"
        >
          <span
            v-for="part in context"
            :key="part.key"
            class="inline-flex items-baseline min-w-0 gap-1.5"
          >
            <span
              class="text-[11px] font-520 uppercase tracking-[0.06em] text-n-slate-10"
            >
              {{ $t(`CRM_KANBAN.META_ADS_HUB.AD_DETAIL.${part.key}`) }}
            </span>
            <span class="min-w-0">{{ part.name }}</span>
          </span>
        </p>
      </header>

      <div
        class="grid items-start gap-5 lg:grid-cols-[minmax(0,2fr)_minmax(0,3fr)]"
      >
        <figure
          class="flex flex-col gap-2 m-0 overflow-hidden border border-solid rounded-xl border-n-weak bg-n-solid-1"
        >
          <div class="flex justify-center bg-n-alpha-1">
            <img
              v-if="ad.thumbnail_url && brokenImage !== ad.thumbnail_url"
              :src="ad.thumbnail_url"
              :alt="ad.name || ''"
              data-ad-detail-image
              class="block object-contain w-full h-auto max-h-[40rem]"
              @error="brokenImage = ad.thumbnail_url"
            />
            <div
              v-else
              data-ad-detail-placeholder
              class="grid w-full aspect-[4/3] lg:aspect-square place-items-center bg-gradient-to-br"
              :class="thumbClass(ad.ad_id)"
            >
              <span
                class="i-lucide-image size-10 text-white/50"
                aria-hidden="true"
              />
            </div>
          </div>
          <figcaption v-if="ad.preview_url" class="px-4 pb-3">
            <a
              :href="ad.preview_url"
              target="_blank"
              rel="noopener noreferrer"
              data-ad-detail-preview
              class="inline-flex items-center gap-1.5 text-[13px] font-440 no-underline min-h-11 text-n-blue-11 hover:underline"
            >
              {{ $t('CRM_KANBAN.META_ADS_HUB.AD_DETAIL.PREVIEW') }}
              <span
                class="i-lucide-external-link size-3.5"
                aria-hidden="true"
              />
            </a>
          </figcaption>
        </figure>

        <div class="flex flex-col gap-5">
          <span
            :data-verdict="ad.verdict"
            class="self-start px-2.5 py-1 text-xs font-520 uppercase tracking-[0.06em] rounded"
            :class="VERDICT_CLASSES[ad.verdict]"
          >
            {{
              $t(
                `CRM_KANBAN.META_ADS_HUB.PANEL.VERDICT.${ad.verdict.toUpperCase()}`
              )
            }}
          </span>

          <!-- A coluna da direita é estreita entre lg e 2xl: ali os quadrados ficam dois a dois. -->
          <dl
            class="grid grid-cols-2 gap-3 m-0 sm:grid-cols-4 lg:grid-cols-2 2xl:grid-cols-4"
          >
            <div
              v-for="tile in tiles"
              :key="tile.key"
              :data-ad-detail-tile="tile.key"
              class="flex flex-col gap-1.5 p-4 border border-solid rounded-xl border-n-weak bg-n-solid-1 min-w-0"
            >
              <dt
                class="text-[11px] font-520 uppercase tracking-[0.06em] text-n-slate-10"
              >
                {{ $t(`CRM_KANBAN.META_ADS_HUB.AD_DETAIL.TILES.${tile.key}`) }}
              </dt>
              <!-- mt-auto: rótulo que quebra em duas linhas não tira o número da linha dos outros. -->
              <dd
                class="m-0 mt-auto text-xl truncate font-interDisplay font-520 tracking-[-0.02em] tabular-nums"
                :class="tile.tone"
              >
                {{ tile.value }}
              </dd>
            </div>
          </dl>

          <div
            data-ad-detail-why
            :data-reason="reason.kind"
            class="flex flex-col gap-2 p-5 border border-solid rounded-xl border-n-weak bg-n-solid-1"
          >
            <h4
              class="m-0 text-xs font-520 uppercase tracking-[0.08em] text-n-slate-11"
            >
              {{ $t('CRM_KANBAN.META_ADS_HUB.AD_DETAIL.WHY_TITLE') }}
            </h4>
            <p
              class="m-0 text-[15px] font-420 leading-relaxed text-n-slate-12 text-pretty"
            >
              {{ reasonText }}
            </p>
            <div
              v-if="reason.kind === 'early' && openQuotes"
              data-ad-detail-meanwhile
              class="flex flex-col gap-1 pt-3 mt-1 border-0 border-t border-solid border-n-weak"
            >
              <span
                class="text-xs font-520 uppercase tracking-[0.08em] text-n-slate-11"
              >
                {{ $t('CRM_KANBAN.META_ADS_HUB.AD_DETAIL.MEANWHILE_TITLE') }}
              </span>
              <span class="text-sm font-420 leading-relaxed text-n-slate-12">
                {{
                  $t(
                    'CRM_KANBAN.META_ADS_HUB.AD_DETAIL.MEANWHILE',
                    { count: openQuotes },
                    openQuotes
                  )
                }}
              </span>
              <button
                type="button"
                data-ad-detail-meanwhile-see
                class="inline-flex items-center self-start gap-1 p-0 text-[13px] font-440 bg-transparent border-0 min-h-11 text-n-blue-11 hover:underline focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
                @click="showQuotes"
              >
                {{ $t('CRM_KANBAN.META_ADS_HUB.AD_DETAIL.MEANWHILE_SEE') }}
                <span class="i-lucide-arrow-down size-3.5" aria-hidden="true" />
              </button>
            </div>
          </div>
        </div>
      </div>

      <div
        class="flex flex-col gap-4 p-5 border border-solid rounded-xl border-n-weak bg-n-solid-1 sm:p-6"
      >
        <div class="flex flex-wrap items-center justify-between gap-3">
          <h4
            class="m-0 text-xs font-520 uppercase tracking-[0.08em] text-n-slate-11"
          >
            {{ $t('CRM_KANBAN.META_ADS_HUB.AD_DETAIL.CHART_TITLE') }}
          </h4>
          <ul
            class="flex gap-4 p-0 m-0 text-xs list-none font-440 text-n-slate-11"
          >
            <li class="flex items-center gap-1.5">
              <span
                class="rounded-sm size-2.5 bg-n-blue-8"
                aria-hidden="true"
              />
              {{ $t('CRM_KANBAN.META_ADS_HUB.AD_DETAIL.LEGEND_SPEND') }}
            </li>
            <li class="flex items-center gap-1.5">
              <span
                class="rounded-full size-2.5 bg-n-teal-10"
                aria-hidden="true"
              />
              {{ $t('CRM_KANBAN.META_ADS_HUB.AD_DETAIL.LEGEND_CONVERSATIONS') }}
            </li>
          </ul>
        </div>
        <p
          data-ad-detail-chart-scale
          class="m-0 text-xs font-420 tabular-nums text-n-slate-11"
        >
          {{
            $t(
              'CRM_KANBAN.META_ADS_HUB.AD_DETAIL.CHART_SCALE',
              { spend: chart.maxSpend, count: chart.maxTalks },
              chart.maxTalks
            )
          }}
        </p>
        <!-- O desenho é só para ver; os números de cada dia estão na tabela logo abaixo (toque e leitor de tela). -->
        <svg
          data-ad-detail-chart
          aria-hidden="true"
          :viewBox="`0 0 ${CHART.width} ${CHART.height}`"
          preserveAspectRatio="none"
          class="block w-full h-40 overflow-visible sm:h-48"
        >
          <line
            x1="0"
            :x2="CHART.width"
            :y1="CHART.height"
            :y2="CHART.height"
            class="stroke-n-slate-6"
            stroke-width="1"
            vector-effect="non-scaling-stroke"
          />
          <g v-for="day in chart.days" :key="day.date">
            <rect
              data-ad-detail-bar
              :x="day.x"
              :y="day.y"
              :width="day.width"
              :height="day.height"
              class="fill-n-blue-8"
            >
              <title>{{ day.title }}</title>
            </rect>
            <template v-if="day.dot !== null">
              <line
                :x1="day.center"
                :x2="day.center"
                :y1="day.dot"
                :y2="day.dot"
                stroke-width="12"
                stroke-linecap="round"
                vector-effect="non-scaling-stroke"
                class="stroke-n-solid-1"
              />
              <line
                data-ad-detail-dot
                :x1="day.center"
                :x2="day.center"
                :y1="day.dot"
                :y2="day.dot"
                stroke-width="8"
                stroke-linecap="round"
                vector-effect="non-scaling-stroke"
                class="stroke-n-teal-10"
              >
                <title>{{ day.title }}</title>
              </line>
            </template>
          </g>
        </svg>
        <p
          class="flex justify-between m-0 text-xs font-420 tabular-nums text-n-slate-10"
          aria-hidden="true"
        >
          <span v-for="label in axis" :key="label">{{ label }}</span>
        </p>
        <details data-ad-detail-days class="group">
          <summary
            class="inline-flex items-center gap-1.5 text-[13px] font-440 cursor-pointer list-none min-h-11 text-n-blue-11 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand [&::-webkit-details-marker]:hidden"
          >
            {{ $t('CRM_KANBAN.META_ADS_HUB.AD_DETAIL.DAYS_TOGGLE') }}
            <span
              class="i-lucide-chevron-down size-3.5 group-open:rotate-180"
              aria-hidden="true"
            />
          </summary>
          <table class="w-full text-sm border-collapse font-420 tabular-nums">
            <thead>
              <tr
                class="text-[11px] font-520 uppercase tracking-[0.06em] text-n-slate-10"
              >
                <th scope="col" class="py-2 font-520 text-start">
                  {{ $t('CRM_KANBAN.META_ADS_HUB.AD_DETAIL.DAYS_DATE') }}
                </th>
                <th scope="col" class="py-2 font-520 text-end">
                  {{ $t('CRM_KANBAN.META_ADS_HUB.AD_DETAIL.LEGEND_SPEND') }}
                </th>
                <th scope="col" class="py-2 font-520 text-end">
                  {{
                    $t('CRM_KANBAN.META_ADS_HUB.AD_DETAIL.LEGEND_CONVERSATIONS')
                  }}
                </th>
              </tr>
            </thead>
            <tbody>
              <tr
                v-for="day in chart.days"
                :key="day.date"
                data-ad-detail-day
                class="border-0 border-t border-solid border-n-weak text-n-slate-12"
              >
                <th scope="row" class="py-2 font-420 text-start">
                  {{ day.label }}
                </th>
                <td class="py-2 text-end">{{ day.spend }}</td>
                <td class="py-2 text-end">{{ day.talks }}</td>
              </tr>
            </tbody>
          </table>
        </details>
      </div>

      <div
        data-ad-detail-quotes
        class="flex flex-col gap-4 p-5 border border-solid rounded-xl border-n-weak bg-n-solid-1 sm:p-6"
      >
        <h4
          ref="quotesHeading"
          tabindex="-1"
          class="m-0 text-xs font-520 uppercase tracking-[0.08em] text-n-slate-11 scroll-mt-4 focus:outline-none"
        >
          {{ $t('CRM_KANBAN.META_ADS_HUB.AD_DETAIL.QUOTES_TITLE') }}
        </h4>
        <p v-if="!quotes.length" class="m-0 text-sm font-420 text-n-slate-11">
          {{ $t('CRM_KANBAN.META_ADS_HUB.AD_DETAIL.QUOTES_EMPTY') }}
        </p>
        <ul v-else class="flex flex-col gap-2 p-0 m-0 list-none">
          <li
            v-for="card in quotes"
            :key="card.card_id"
            :data-ad-detail-quote="card.card_id"
            class="flex flex-wrap items-center gap-4 px-4 py-3 border border-solid rounded-lg border-n-weak"
          >
            <!-- No celular o título ocupa a linha toda e o valor e o botão descem; a partir de sm, dividem a linha. -->
            <span class="min-w-0 basis-full sm:basis-0 sm:flex-1">
              <span class="block text-sm font-520 truncate text-n-slate-12">
                {{ card.title }}
              </span>
              <span
                class="flex flex-wrap items-center text-xs font-420 gap-x-2 text-n-slate-10"
              >
                <span v-if="card.stage_name">{{ card.stage_name }}</span>
                <span
                  v-if="card.status === 'won'"
                  data-ad-detail-quote-won
                  class="px-1.5 rounded font-520 bg-n-teal-3 text-n-teal-11"
                >
                  {{ $t('CRM_KANBAN.META_ADS_HUB.AD_DETAIL.WON') }}
                </span>
                <span v-else-if="card.waiting_since">
                  {{
                    $t('CRM_KANBAN.META_ADS_HUB.PANEL.STALLED_SINCE', {
                      time: waitingFor(card.waiting_since),
                    })
                  }}
                </span>
              </span>
            </span>
            <span
              class="text-base font-interDisplay font-520 tabular-nums text-n-slate-12"
            >
              {{ fmt(card.value) }}
            </span>
            <router-link
              v-if="card.conversation_id"
              :to="conversationLink(card.conversation_id)"
              class="inline-flex items-center px-3 text-[13px] font-440 no-underline border border-solid rounded-lg min-h-11 border-n-weak text-n-slate-12 hover:bg-n-alpha-1"
            >
              {{ $t('CRM_KANBAN.META_ADS_HUB.PANEL.OPEN_CONVERSATION') }}
            </router-link>
          </li>
        </ul>
      </div>
    </template>
  </section>
</template>
