<script setup>
import { computed, onBeforeUnmount, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useEmitter } from 'dashboard/composables/emitter';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import CrmMetaAdsConnectionAPI from 'dashboard/api/crmMetaAdsConnection';
import CtwaTrackedLinksAPI from 'dashboard/api/ctwaTrackedLinks';
import { errorMessageKey, intlLocale, relativeTime } from '../metaAdsHelpers';

// Anúncios da Meta (#1068): a conexão pronta. Herói com a frase da conta, quatro quadros com o que está
// ligado de verdade (WhatsApp, site, campanhas com nome, funis avisando a Meta), o que acontece agora e um
// atalho para cada passo. "Precisa de atenção" quando a Meta recusou o acesso salvo.
//
// Gasto (#1073): pedido ao abrir, a cada REFRESH_MS enquanto a aba está visível e ao voltar para ela; o
// servidor só chama a Meta se o número tiver mais de 2 minutos. O fim da leitura chega pelo canal de tempo
// real; se ele não chegar (conexão caída), a tela confere de novo em CHECK_MS, para o "atualizando…" nunca
// ficar preso.
const props = defineProps({
  connection: { type: Object, required: true },
});

const emit = defineEmits(['removed', 'reconnect', 'open']);

const { t, locale } = useI18n();
const removeDialog = ref(null);
const removing = ref(false);
const sitePages = ref([]);
const funnels = ref(null);
const insights = ref(null);
const REFRESH_MS = 2 * 60 * 1000;
const CHECK_MS = 20 * 1000;
let refreshTimer = null;
// Fora da tela não agenda nada: uma resposta que chega depois de sair não pode deixar timer órfão.
let unmounted = false;

const attention = computed(() => props.connection.status !== 'active');
const attentionHint = computed(() =>
  props.connection.last_error === 'ad_account_access_lost'
    ? t('CRM_KANBAN.META_ADS_HUB.SUMMARY.ACCESS_LOST_HINT')
    : t('CRM_KANBAN.META_ADS_HUB.SUMMARY.ATTENTION_HINT')
);
const partnerName = computed(
  () => props.connection.partner?.business_name || 'Hub2You'
);
const via = computed(() =>
  props.connection.mode === 'partner'
    ? t('CRM_KANBAN.META_ADS_HUB.SUMMARY.MODE_PARTNER', {
        partner: partnerName.value,
      })
    : t('CRM_KANBAN.META_ADS_HUB.SUMMARY.MODE_TOKEN')
);
const verified = computed(() => {
  const time = relativeTime(
    props.connection.verified_at || props.connection.last_checked_at,
    locale.value
  );
  return time ? t('CRM_KANBAN.META_ADS_HUB.SUMMARY.VERIFIED', { time }) : null;
});
const destinations = computed(() => props.connection.destinations || {});

const lastSiteClick = computed(() => {
  const times = sitePages.value
    .map(page => page.last_signal_at)
    .filter(Boolean)
    .sort();
  return relativeTime(times[times.length - 1], locale.value);
});
const namedCampaigns = computed(
  () =>
    new Set(
      sitePages.value.flatMap(page =>
        (page.campaigns || []).filter(row => row.name).map(row => row.name)
      )
    ).size
);
const readyFunnels = computed(
  () => (funnels.value?.funnels || []).filter(f => !f.missing.length).length
);
const totalFunnels = computed(() => funnels.value?.funnels?.length || 0);

const tiles = computed(() => [
  {
    key: 'WHATSAPP',
    icon: 'i-lucide-message-circle',
    step: 3,
    on: Boolean(destinations.value.whatsapp),
    value: destinations.value.whatsapp
      ? t('CRM_KANBAN.META_ADS_HUB.SUMMARY.TILE_ON')
      : t('CRM_KANBAN.META_ADS_HUB.SUMMARY.TILE_OFF'),
  },
  {
    key: 'SITE',
    icon: 'i-lucide-globe',
    step: 3,
    on: Boolean(destinations.value.site && lastSiteClick.value),
    value: !destinations.value.site
      ? t('CRM_KANBAN.META_ADS_HUB.SUMMARY.TILE_OFF')
      : lastSiteClick.value ||
        t('CRM_KANBAN.META_ADS_HUB.SUMMARY.SITE_WAITING'),
  },
  {
    key: 'CAMPAIGNS',
    icon: 'i-lucide-tag',
    step: 3,
    on: namedCampaigns.value > 0,
    value: String(namedCampaigns.value),
  },
  {
    key: 'FUNNELS',
    icon: 'i-lucide-kanban',
    step: 4,
    on: totalFunnels.value > 0 && readyFunnels.value === totalFunnels.value,
    value: funnels.value
      ? t('CRM_KANBAN.META_ADS_HUB.SUMMARY.FUNNELS_VALUE', {
          ready: readyFunnels.value,
          total: totalFunnels.value,
        })
      : '…',
  },
]);

// "2026-10-06" é o dia da conta de anúncios, sem hora. O servidor diz qual é hoje no fuso da conta (`today`);
// sem fuso conhecido, vale a data de quem vê.
const localDay = () => {
  const now = new Date();
  const pad = value => String(value).padStart(2, '0');
  return `${now.getFullYear()}-${pad(now.getMonth() + 1)}-${pad(now.getDate())}`;
};

const spendMoney = computed(() => {
  const data = insights.value;
  if (!data?.date) return null;
  return new Intl.NumberFormat(intlLocale(locale.value), {
    style: 'currency',
    currency: data.currency || 'BRL',
  }).format(Number(data.spend));
});
const spendLabel = computed(() => {
  const data = insights.value;
  if (!spendMoney.value) return null;
  if (data.date === (data.today || localDay())) {
    return t('CRM_KANBAN.META_ADS_HUB.SUMMARY.SPEND_TODAY');
  }
  const date = new Date(`${data.date}T12:00:00`).toLocaleDateString(
    intlLocale(locale.value),
    { day: '2-digit', month: '2-digit' }
  );
  return t('CRM_KANBAN.META_ADS_HUB.SUMMARY.SPEND_ON', { date });
});
const spendUpdated = computed(() => {
  const time = relativeTime(insights.value?.synced_at, locale.value);
  return time
    ? t('CRM_KANBAN.META_ADS_HUB.SUMMARY.SPEND_UPDATED', { time })
    : null;
});

const NEXT = ['NEXT_NAMES', 'NEXT_SALES', 'NEXT_PANEL'];

// "Quanto confiar" (#1073, F2b): conversas que vieram de anúncio nos últimos 30 dias, pelo melhor que sabemos
// de cada uma. Do mais forte ao mais fraco.
const CONFIDENCE_LEVELS = [
  { key: 'ad', label: 'AD', dot: 'bg-n-teal-9' },
  { key: 'ad_name', label: 'AD_NAME', dot: 'bg-n-teal-7' },
  { key: 'campaign', label: 'CAMPAIGN', dot: 'bg-n-amber-9' },
  { key: 'unknown', label: 'UNKNOWN', dot: 'bg-n-slate-8' },
];
const confidence = computed(() => insights.value?.confidence || null);
const confidentShare = computed(() => {
  const data = confidence.value;
  if (!data?.conversations) return null;
  return Math.round(((data.ad + data.ad_name) / data.conversations) * 100);
});
const confidenceGap = computed(
  () => (confidence.value?.campaign || 0) + (confidence.value?.unknown || 0)
);

const pageVisible = () => document.visibilityState !== 'hidden';

// Próxima conferência: rápida enquanto há leitura ou carga em andamento; com a aba escondida, só reagenda.
const scheduleRefresh = reload => {
  clearTimeout(refreshTimer);
  if (unmounted) return;
  const waiting = insights.value?.refreshing || insights.value?.backfilling;
  refreshTimer = setTimeout(
    () => (pageVisible() ? reload() : scheduleRefresh(reload)),
    waiting ? CHECK_MS : REFRESH_MS
  );
};

// Falha de rede mantém o último número na tela; a próxima rodada tenta de novo.
const loadInsights = async () => {
  try {
    const { data } = await CrmMetaAdsConnectionAPI.insights();
    insights.value = data.insights;
  } catch {
    // mantém o que já estava na tela
  } finally {
    scheduleRefresh(loadInsights);
  }
};

const onVisibility = () => {
  if (pageVisible() && !attention.value) loadInsights();
};

useEmitter(BUS_EVENTS.CRM_META_ADS_INSIGHTS_UPDATED, data => {
  insights.value = { ...data, refreshing: false };
  scheduleRefresh(loadInsights);
});

const load = async () => {
  const [links, funnelData] = await Promise.allSettled([
    CtwaTrackedLinksAPI.get(),
    CrmMetaAdsConnectionAPI.funnels(),
  ]);
  if (links.status === 'fulfilled') {
    sitePages.value = (links.value.data.payload || []).filter(
      link => link.usage === 'website'
    );
  }
  if (funnelData.status === 'fulfilled') funnels.value = funnelData.value.data;
};

const remove = async () => {
  removing.value = true;
  try {
    await CrmMetaAdsConnectionAPI.remove();
    useAlert(t('CRM_KANBAN.META_ADS_HUB.SUMMARY.REMOVED'));
    removeDialog.value?.close();
    emit('removed');
  } catch (error) {
    useAlert(t(errorMessageKey(error)));
  } finally {
    removing.value = false;
  }
};

onMounted(() => {
  load();
  if (attention.value) return;

  loadInsights();
  document.addEventListener('visibilitychange', onVisibility);
});

onBeforeUnmount(() => {
  unmounted = true;
  clearTimeout(refreshTimer);
  document.removeEventListener('visibilitychange', onVisibility);
});
</script>

<template>
  <section data-meta-ads-summary class="flex flex-col gap-5">
    <div
      class="relative flex flex-col gap-4 p-5 overflow-hidden text-white rounded-2xl sm:p-7"
      :class="attention ? 'bg-n-amber-11' : 'bg-[#0D2344]'"
    >
      <span
        aria-hidden="true"
        class="absolute rounded-full pointer-events-none -end-16 -top-24 size-72 border-[2.5rem] border-n-blue-9 opacity-15"
      />
      <div class="relative flex flex-col gap-2">
        <span
          class="inline-flex items-center gap-2 text-xs font-semibold tracking-wider uppercase"
          :class="attention ? 'text-n-amber-3' : 'text-n-teal-6'"
        >
          <span
            class="size-4"
            :class="
              attention ? 'i-lucide-triangle-alert' : 'i-lucide-circle-check'
            "
            aria-hidden="true"
          />
          {{
            attention
              ? $t('CRM_KANBAN.META_ADS_HUB.SUMMARY.ATTENTION')
              : $t('CRM_KANBAN.META_ADS_HUB.SUMMARY.EYEBROW')
          }}
        </span>
        <h3
          class="m-0 text-2xl font-semibold leading-tight tracking-tight text-white sm:text-3xl text-balance"
        >
          {{
            attention
              ? attentionHint
              : $t('CRM_KANBAN.META_ADS_HUB.SUMMARY.HEADLINE', {
                  account: connection.ad_account?.name || '',
                })
          }}
        </h3>
        <p
          v-if="!attention && insights"
          data-summary-spend
          class="flex flex-wrap items-baseline m-0 text-sm text-n-blue-4 gap-x-3 gap-y-1"
          aria-live="polite"
        >
          <template v-if="spendLabel">
            <span>
              {{ spendLabel }}
              <strong
                data-summary-spend-value
                class="text-lg font-semibold text-white"
              >
                {{ spendMoney }}
              </strong>
            </span>
            <span>
              {{
                $t('CRM_KANBAN.META_ADS_HUB.SUMMARY.SPEND_CONVERSATIONS', {
                  count: insights.ad_conversations_today ?? 0,
                })
              }}
            </span>
          </template>
          <span v-else-if="!insights.backfilling">
            {{ $t('CRM_KANBAN.META_ADS_HUB.SUMMARY.SPEND_EMPTY') }}
          </span>
          <span
            v-if="insights.backfilling"
            data-summary-spend-backfilling
            class="inline-flex items-center gap-1"
          >
            <span
              class="i-lucide-loader-circle size-3.5 animate-spin"
              aria-hidden="true"
            />
            {{ $t('CRM_KANBAN.META_ADS_HUB.SUMMARY.SPEND_BACKFILLING') }}
          </span>
          <span v-if="spendUpdated">{{ spendUpdated }}</span>
          <span
            v-if="insights.refreshing"
            data-summary-spend-refreshing
            class="inline-flex items-center gap-1"
          >
            <span
              class="i-lucide-refresh-cw size-3.5 animate-spin"
              aria-hidden="true"
            />
            {{ $t('CRM_KANBAN.META_ADS_HUB.SUMMARY.SPEND_REFRESHING') }}
          </span>
        </p>
        <p class="flex flex-wrap m-0 text-sm text-n-blue-4 gap-x-3 gap-y-1">
          <span>{{ via }}</span>
          <span>
            {{
              connection.pixel
                ? $t('CRM_KANBAN.META_ADS_HUB.SUMMARY.PIXEL', {
                    pixel: connection.pixel.name || connection.pixel.id,
                  })
                : $t('CRM_KANBAN.META_ADS_HUB.SUMMARY.NO_PIXEL')
            }}
          </span>
          <span v-if="verified">{{ verified }}</span>
        </p>
      </div>
      <div class="relative flex flex-wrap gap-2">
        <Button
          v-if="attention"
          data-summary-reconnect
          class="!min-h-11 !rounded-xl"
          icon="i-lucide-plug"
          :label="$t('CRM_KANBAN.META_ADS_HUB.SUMMARY.RECONNECT')"
          @click="emit('reconnect')"
        />
        <router-link
          v-else
          data-summary-crm
          :to="{ name: 'crm_kanban_index' }"
          class="inline-flex items-center gap-2 px-4 text-sm font-semibold no-underline bg-white rounded-xl min-h-11 text-[#0D2344] hover:bg-n-blue-2 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-white"
        >
          <span class="i-lucide-kanban size-4" aria-hidden="true" />
          {{ $t('CRM_KANBAN.META_ADS_HUB.SUMMARY.OPEN_CRM') }}
        </router-link>
      </div>
    </div>

    <ul class="grid gap-3 p-0 m-0 list-none sm:grid-cols-2">
      <li v-for="tile in tiles" :key="tile.key" :data-summary-tile="tile.key">
        <button
          type="button"
          class="flex items-center w-full gap-3 px-4 py-3 text-left border border-solid shadow-sm min-h-[4.5rem] rounded-2xl border-n-weak bg-n-solid-1 hover:bg-n-alpha-1 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
          @click="emit('open', tile.step)"
        >
          <span
            class="grid flex-none rounded-xl size-10 place-items-center"
            :class="
              tile.on
                ? 'bg-n-teal-3 text-n-teal-11'
                : 'bg-n-alpha-2 text-n-slate-11'
            "
            aria-hidden="true"
          >
            <span :class="tile.icon" class="size-5" />
          </span>
          <span class="flex flex-col flex-1 min-w-0">
            <span class="text-xs text-n-slate-11">
              {{ $t(`CRM_KANBAN.META_ADS_HUB.SUMMARY.TILE_${tile.key}`) }}
            </span>
            <span class="text-base font-semibold truncate text-n-slate-12">
              {{ tile.value }}
            </span>
          </span>
          <span
            class="flex-none i-lucide-chevron-right size-4 text-n-slate-9"
            aria-hidden="true"
          />
        </button>
      </li>
    </ul>

    <div
      v-if="!attention && confidence"
      data-summary-confidence
      class="flex flex-col gap-3 p-4 border shadow-sm rounded-2xl border-n-weak bg-n-solid-1 sm:p-5"
    >
      <div class="flex flex-wrap items-baseline justify-between gap-2">
        <h4 class="m-0 text-base font-semibold text-n-slate-12">
          {{ $t('CRM_KANBAN.META_ADS_HUB.SUMMARY.CONFIDENCE.TITLE') }}
        </h4>
        <span
          v-if="confidentShare !== null"
          data-summary-confidence-share
          class="text-2xl font-semibold text-n-slate-12"
        >
          {{
            $t('CRM_KANBAN.META_ADS_HUB.SUMMARY.CONFIDENCE.SHARE', {
              share: confidentShare,
            })
          }}
        </span>
      </div>
      <p class="m-0 text-sm text-n-slate-11">
        {{
          confidence.conversations
            ? $t('CRM_KANBAN.META_ADS_HUB.SUMMARY.CONFIDENCE.TOTAL', {
                days: confidence.window_days,
                count: confidence.conversations,
              })
            : $t('CRM_KANBAN.META_ADS_HUB.SUMMARY.CONFIDENCE.EMPTY')
        }}
      </p>
      <ul
        v-if="confidence.conversations"
        class="grid gap-2 p-0 m-0 list-none sm:grid-cols-2"
      >
        <li
          v-for="level in CONFIDENCE_LEVELS"
          :key="level.key"
          :data-confidence-level="level.key"
          class="flex items-center gap-2 text-sm text-n-slate-12"
        >
          <span
            class="flex-none rounded-full size-2.5"
            :class="level.dot"
            aria-hidden="true"
          />
          <span class="flex-1 min-w-0">
            {{
              $t(`CRM_KANBAN.META_ADS_HUB.SUMMARY.CONFIDENCE.${level.label}`)
            }}
          </span>
          <span class="font-semibold tabular-nums">
            {{ confidence[level.key] }}
          </span>
        </li>
      </ul>
      <button
        v-if="confidenceGap"
        type="button"
        data-summary-confidence-fix
        class="self-start p-0 text-sm font-medium text-left bg-transparent border-0 min-h-11 text-n-blue-11 hover:underline focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
        @click="emit('open', 3)"
      >
        {{ $t('CRM_KANBAN.META_ADS_HUB.SUMMARY.CONFIDENCE.FIX') }}
      </button>
    </div>

    <div
      v-if="!attention"
      class="flex flex-col gap-3 p-4 border shadow-sm rounded-2xl border-n-weak bg-n-solid-1 sm:p-5"
    >
      <h4 class="m-0 text-base font-semibold text-n-slate-12">
        {{ $t('CRM_KANBAN.META_ADS_HUB.SUMMARY.NEXT_TITLE') }}
      </h4>
      <ol class="flex flex-col gap-2 p-0 m-0 list-none">
        <li
          v-for="(item, index) in NEXT"
          :key="item"
          class="flex items-start gap-3 text-sm text-n-slate-12"
        >
          <span
            class="grid flex-none text-xs font-semibold rounded-full size-6 place-items-center bg-n-blue-3 text-n-blue-11"
            aria-hidden="true"
          >
            {{ index + 1 }}
          </span>
          {{ $t(`CRM_KANBAN.META_ADS_HUB.SUMMARY.${item}`) }}
        </li>
      </ol>
    </div>

    <div>
      <Button
        data-summary-remove
        class="!min-h-11 !rounded-xl"
        variant="ghost"
        color="ruby"
        size="sm"
        icon="i-lucide-unplug"
        :label="$t('CRM_KANBAN.META_ADS_HUB.SUMMARY.REMOVE')"
        @click="removeDialog?.open()"
      />
    </div>

    <Dialog
      ref="removeDialog"
      type="alert"
      :title="$t('CRM_KANBAN.META_ADS_HUB.SUMMARY.REMOVE_TITLE')"
      :description="$t('CRM_KANBAN.META_ADS_HUB.SUMMARY.REMOVE_HINT')"
      :confirm-button-label="$t('CRM_KANBAN.META_ADS_HUB.SUMMARY.REMOVE')"
      :is-loading="removing"
      @confirm="remove"
    />
  </section>
</template>
