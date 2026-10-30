<script setup>
import { computed, nextTick, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import CrmMetaAdsConnectionAPI from 'dashboard/api/crmMetaAdsConnection';
import { useAlert } from 'dashboard/composables';
import { conversationUrl, frontendURL } from 'dashboard/helper/URLHelper';
import {
  DEFAULT_PERIOD,
  MORE_PERIODS,
  ROLLING_PERIODS,
  VERDICT_CLASSES,
  adImage,
  amount,
  duration,
  periodRange,
  relativeTime,
  rollingDays,
  thumbClass,
} from '../metaAdsHelpers';
import { useMetaAdsLive } from '../useMetaAdsLive';
import MetaAdsConfidence from './MetaAdsConfidence.vue';
import MetaAdsAdDetail from './MetaAdsAdDetail.vue';
import MetaAdsDailyAction from './MetaAdsDailyAction.vue';
import MetaAdsPathList from './MetaAdsPathList.vue';
import MetaAdsQuoteMessage from './MetaAdsQuoteMessage.vue';
import MetaAdsReportButton from './MetaAdsReportButton.vue';
import MetaAdsCreate from './MetaAdsCreate.vue';
import MetaAdsPausedAds from './MetaAdsPausedAds.vue';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import { useMapGetter } from 'dashboard/composables/store';

// Anúncios da Meta (#1088, F3a): o painel do dia a dia do mockup aprovado. Uma frase com o dinheiro, a ação do
// dia com o porquê, o caminho investido → conversas → propostas → vendas, cada anúncio por venda com o veredito
// em palavras e o quanto confiar nos números. Tudo do servidor (Crm::MetaAds::Panel::Report); a tela só
// formata. Fica viva como o resumo (useMetaAdsLive).
//
// F5 (#1110): "O que fazer hoje" vira a lista de até 3 ações do consultor (panel.advice); Conversas, Propostas e
// Vendas abrem a lista da etapa ali mesmo (MetaAdsPathList, uma por vez, fora do endereço); a etapa Conversas
// mostra o tempo de resposta; "Quanto confiar" ganha o número da Meta ao lado do nosso.
//
// Sem conexão (Anúncios sem login, #1960, panel.source 'whatsapp'): o mesmo painel com o que o WhatsApp contou,
// sem gasto, custo, veredito, consultor nem "quanto confiar". `sample` (período → painel) mostra números de
// exemplo, sem servidor e sem abrir anúncio ou lista.
//
// Conectar a conta de anúncios (#2054): sem conexão, o caminho começa num "Investimento" sem valor, com "Ver quanto
// gastei" (emite 'connect'). Com conexão, os anúncios que não levam ao WhatsApp ficam num bloco à parte ("Outros
// anúncios", panel.other_ads), com gasto, cliques e vezes que apareceram, fora do custo por conversa e por venda.
const props = defineProps({
  // Quem só tem meta_ads_view (#1794): o painel sem os gestos do consultor nem os atalhos para a conexão.
  readOnly: { type: Boolean, default: false },
  sample: { type: Function, default: null },
});
const emit = defineEmits(['open', 'connect']);

const { t, locale } = useI18n();
const route = useRoute();
const router = useRouter();
// Período (#2011): 7, 30 ou 90 dias nos botões; este mês, mês passado e desde o primeiro anúncio no "Mais
// períodos". O nome vai ao servidor, que devolve as datas (from/to) já no fuso da conta.
const period = ref(DEFAULT_PERIOD);
const PERIOD_KEYS = 'CRM_KANBAN.META_ADS_HUB.PANEL.PERIODS';
const periodName = key => t(`${PERIOD_KEYS}.${key}.NAME`);
const moreOptions = computed(() =>
  MORE_PERIODS.map(key => ({ value: key, label: periodName(key) }))
);
// Exemplo (sem servidor): os números de exemplo só existem por número de dias.
const samplePanel = key => props.sample(rollingDays(key) || 30);
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

// Criar anúncio (#2198, flag meta_ads_criar), lembrado no endereço (?criar=) como o anúncio aberto. Só com a conexão
// (não no painel sem login) e para quem pode mexer (administrador ou meta_ads_manage).
const isFeatureEnabledonAccount = useMapGetter(
  'accounts/isFeatureEnabledonAccount'
);
// ?criar=novo abre a escolha (ou entra direto no único tipo que o servidor oferece); anuncio e post (impulsionar,
// #2339) já escolhem.
const CREATE_KINDS = {
  novo: null,
  anuncio: 'ad',
  post: 'post',
};
const creatingFromRoute = () =>
  Object.hasOwn(CREATE_KINDS, route.query.criar) ? route.query.criar : null;
const creating = computed(creatingFromRoute);
const canCreate = computed(
  () =>
    !props.readOnly &&
    !props.sample &&
    panel.value?.source !== 'whatsapp' &&
    isFeatureEnabledonAccount.value(
      Number(route.params.accountId),
      FEATURE_FLAGS.META_ADS_CRIAR
    )
);
const showCreate = computed(() => Boolean(creating.value && canCreate.value));
const startCreating = kind => {
  router.replace({ query: { ...route.query, criar: kind } });
};
const stopCreating = () => {
  const query = { ...route.query };
  delete query.criar;
  router.replace({ query });
};
// Sem a flag, o topo e o botão do relatório ficam com a marcação de antes (o v-else-if do relatório); com ela, o
// "Criar anúncio" entra ao lado do relatório.
// Pausados à espera (#2198): com eles à vista, o "Ativar anúncio" é o primário e o "Criar anúncio" vira contorno.
const pausedCount = ref(0);

watch(anuncioFromRoute, value => {
  const closed = openAd.value;
  openAd.value = value;
  if (!value && closed) focusCard(closed);
});

const live = useMetaAdsLive({
  // Troca de período no meio de uma leitura: a resposta do período antigo é descartada. Se a troca falha, a tela
  // volta ao período dos números que ela mostra e avisa; a próxima rodada segue tentando o período da tela.
  load: async () => {
    const asked = period.value;
    try {
      const { data } = await CrmMetaAdsConnectionAPI.panel(asked);
      if (asked !== period.value) return;
      panel.value = data.panel;
      loading.value = false;
    } catch (error) {
      if (asked === period.value && panel.value?.period) {
        period.value = panel.value.period;
        loading.value = false;
        useAlert(t('CRM_KANBAN.META_ADS_HUB.PANEL.PERIOD_ERROR'));
      }
      throw error;
    }
  },
  // A IA escrevendo em outra aba também é espera: o texto chega em segundos, não em 2 minutos.
  waiting: () =>
    panel.value?.refreshing ||
    panel.value?.advice?.writer?.status === 'writing',
});

const choosePeriod = value => {
  if (!value || value === period.value) return;
  period.value = value;
  if (props.sample) {
    panel.value = samplePanel(value);
    return;
  }
  loading.value = true;
  live.reload();
};

// O "Mais períodos" mostra o período da tela quando ele é um dos seus; escolher nele troca o período.
const morePeriod = computed({
  get: () => (MORE_PERIODS.includes(period.value) ? period.value : ''),
  set: value => choosePeriod(value),
});

// Trocando de período com números na tela: eles ficam, apagados, até chegar o novo (período longo demora mais).
const switchingPeriod = computed(() => loading.value && Boolean(panel.value));
const periodHint = computed(() =>
  t('CRM_KANBAN.META_ADS_HUB.PANEL.PERIOD_HINT', {
    when: t(`${PERIOD_KEYS}.${period.value}.IN`),
  })
);
// "Este mês · 1 – 21 de out.": o nome e as datas do período que a tela mostra (as do servidor).
const periodContext = computed(() => {
  const shown = panel.value?.period || period.value;
  const range = periodRange(panel.value?.from, panel.value?.to, locale.value);
  const name = periodName(shown);
  return range
    ? t('CRM_KANBAN.META_ADS_HUB.PANEL.PERIOD_CTX', { name, range })
    : name;
});

const withoutSpend = computed(() =>
  ['whatsapp', 'example'].includes(panel.value?.source)
);

// Ninguém de anúncio no período, no painel sem gasto: a tela mostra o aviso em vez dos zeros.
const periodEmpty = computed(
  () => withoutSpend.value && !panel.value?.totals?.conversations
);

const fmt = value => amount(value, panel.value?.currency, locale.value);
const number = value =>
  new Intl.NumberFormat(locale.value.replace('_', '-')).format(value || 0);

const totals = computed(() => panel.value?.totals || {});
const updated = computed(() =>
  relativeTime(panel.value?.synced_at, locale.value)
);

// Contagem com singular e plural: "1 venda", "6 vendas".
const counted = (key, n) =>
  t(`CRM_KANBAN.META_ADS_HUB.PANEL.COUNT.${key}`, { n }, n);

const headline = computed(() =>
  t(
    withoutSpend.value
      ? 'CRM_KANBAN.META_ADS_HUB.PANEL.HEADLINE_WHATSAPP'
      : 'CRM_KANBAN.META_ADS_HUB.PANEL.HEADLINE',
    {
      spend: fmt(totals.value.spend),
      conversations: counted('CONVERSATIONS', totals.value.conversations || 0),
      sales: counted('SALES', totals.value.sales || 0),
    }
  )
);

// As ações do dia vêm prontas do servidor (Advisor::Analysis); o texto de cada uma é feito na própria lista.
const advice = computed(() => panel.value?.advice || null);

// O tempo de resposta do período, na etapa Conversas: some sem resposta medida.
const SLOW_AFTER_SECONDS = 300;
const responseTime = computed(() => {
  const data = panel.value?.response_time;
  if (data?.median_seconds == null) return null;
  return {
    value: duration(data.median_seconds, t),
    slow: data.median_seconds > SLOW_AFTER_SECONDS,
    unanswered: data.unanswered || 0,
  };
});

// Uma lista do caminho aberta por vez. `slow_replies` vem de "O que fazer hoje" e é sempre de 30 dias (o número
// da ação); as etapas seguem o período da tela.
const PATH_LISTS = {
  CONVERSATIONS: 'conversations',
  QUOTES: 'quotes',
  SALES: 'sales',
};
const SLOW_REPLIES_PERIOD = '30d';
const openList = ref(null);
const listPeriod = computed(() =>
  openList.value === 'slow_replies' ? SLOW_REPLIES_PERIOD : period.value
);
const toggleList = step => {
  openList.value = openList.value === step ? null : step;
};

// Sem conexão, quem pode conectar vê o investimento como o primeiro passo do caminho, ainda sem valor.
const canConnect = computed(
  () => panel.value?.source === 'whatsapp' && !props.readOnly && !props.sample
);
const spendStep = computed(() => {
  if (!withoutSpend.value) {
    return [{ key: 'SPEND', value: fmt(totals.value.spend), plural: 2 }];
  }
  return canConnect.value
    ? [
        {
          key: 'SPEND',
          value: '—',
          plural: 2,
          connect: true,
          note: t('CRM_KANBAN.META_ADS_HUB.PANEL.CONNECT_SPEND.NOTE'),
        },
      ]
    : [];
});

const path = computed(() => [
  ...spendStep.value,
  {
    key: 'CONVERSATIONS',
    response: responseTime.value,
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
    // #2075 — sem a chave de valores de venda o servidor manda o valor vazio: a venda fica sem o "somando R$".
    extra:
      totals.value.sales && totals.value.sales_value != null
        ? fmt(totals.value.sales_value)
        : null,
    note:
      totals.value.cost_per_sale != null
        ? t('CRM_KANBAN.META_ADS_HUB.PANEL.PER_SALE', {
            value: fmt(totals.value.cost_per_sale),
          })
        : null,
  },
]);

const ads = computed(() => panel.value?.ads || []);
const otherAds = computed(() => panel.value?.other_ads || []);
// O link de imagem da Meta vence (o "oe=" da URL); imagem que não abre vira o quadro de reserva. Guarda o link
// que falhou por anúncio: quando a renovação diária traz um link novo, a imagem volta sem recarregar a página.
const brokenImages = ref({});
const imageOf = ad => adImage(ad, brokenImages.value[ad.ad_id] || []);
const imageFailed = ad => {
  brokenImages.value = {
    ...brokenImages.value,
    [ad.ad_id]: [...(brokenImages.value[ad.ad_id] || []), imageOf(ad)],
  };
};
// Os três números de cada anúncio: o investido numa linha, conversas e vendas lado a lado embaixo (em três
// colunas o rótulo "Conversas" não cabe no cartão estreito).
// Propostas abertas do anúncio: as propostas incluem as que viraram venda.
const openQuotesOf = ad => Math.max((ad.quotes || 0) - (ad.sales || 0), 0);
const adStats = ad => [
  ...(withoutSpend.value ? [] : [{ key: 'SPEND', value: fmt(ad.spend) }]),
  { key: 'CONVERSATIONS', value: ad.conversations },
  { key: 'SALES', value: ad.sales },
];
// As propostas paradas são sempre uma ação do dia (aberta ou feita); dispensadas, ficam na etapa Propostas.
const stalledAction = computed(
  () =>
    advice.value?.actions?.find(item => item.kind === 'stalled_quotes') || null
);
const stalled = computed(() => stalledAction.value?.cards || []);
const stalledCount = computed(() => stalledAction.value?.facts?.count || 0);
const stalledMore = computed(() => stalledCount.value - stalled.value.length);

const conversationLink = id =>
  frontendURL(conversationUrl({ accountId: route.params.accountId, id }));

const waitingFor = value => relativeTime(value, locale.value);

// A lista aberta pelo botão de uma ação vai para a vista: no celular ela fica bem abaixo do herói.
const showList = selector =>
  nextTick(() =>
    document
      .querySelector(selector)
      ?.scrollIntoView?.({ behavior: 'smooth', block: 'nearest' })
  );

// O botão principal de uma ação do dia, pelo alvo que o servidor deu (§5.1). O link da Meta e o "Entendi" são
// resolvidos na própria lista.
const onAdvice = action => {
  const target = action.button?.target;
  if (target === 'stalled_list') {
    showStalled.value = !showStalled.value;
    if (showStalled.value) showList('[data-panel-stalled]');
  } else if (target === 'slow_replies') {
    toggleList('slow_replies');
    if (openList.value) showList('[data-panel-path-list]');
  } else if (target === 'connection_step') {
    emit('open', action.button.step || 3);
  } else if (target === 'ad_detail' && action.ad_id) {
    rememberAd(String(action.ad_id));
  }
};

const expandedTargets = computed(() => [
  ...(showStalled.value ? ['stalled_list'] : []),
  ...(openList.value === 'slow_replies' ? ['slow_replies'] : []),
]);

onMounted(() => {
  if (!props.sample) {
    live.start();
    return;
  }
  panel.value = samplePanel(period.value);
  loading.value = false;
});
</script>

<template>
  <section data-meta-ads-panel class="flex flex-col gap-5">
    <!-- Período (#2011): a escolha numa linha fixa e, embaixo, o que os números contam. O texto muda de tamanho com o
         período; numa linha só, ele empurraria os botões de lugar a cada troca. -->
    <div v-if="!showCreate" class="flex flex-col gap-2">
      <div class="flex flex-wrap items-center justify-between gap-2">
        <div class="flex flex-wrap items-center gap-2">
          <div
            role="group"
            :aria-label="$t('CRM_KANBAN.META_ADS_HUB.PANEL.PERIOD_LABEL')"
            class="flex gap-1 rounded-2xl bg-n-alpha-1 p-1"
          >
            <button
              v-for="key in ROLLING_PERIODS"
              :key="key"
              type="button"
              :data-panel-period="key"
              :aria-pressed="key === period"
              class="min-h-11 whitespace-nowrap rounded-xl border-0 px-2 text-sm font-medium sm:px-4 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
              :class="
                key === period
                  ? 'bg-n-solid-1 text-n-slate-12 shadow-sm'
                  : 'bg-transparent text-n-slate-11 hover:text-n-slate-12'
              "
              @click="choosePeriod(key)"
            >
              {{ $t(`${PERIOD_KEYS}.${key}.BUTTON`) }}
            </button>
            <!-- "Mais períodos" é o quarto botão do grupo: a escolha padrão do produto (sem <select> nativo), com a
                 cara dos outros três e marcado como eles quando um dos períodos dele é o da tela. -->
            <ChoiceSelect
              v-model="morePeriod"
              data-panel-more-periods
              :options="moreOptions"
              :aria-label="$t('CRM_KANBAN.META_ADS_HUB.PANEL.MORE_PERIODS')"
              :placeholder="$t('CRM_KANBAN.META_ADS_HUB.PANEL.MORE_PERIODS')"
              class="[&_[role=combobox]:focus-visible]:ring-2 [&_[role=combobox]:focus-visible]:ring-n-brand [&_[role=combobox]>span:first-child]:text-current [&_[role=combobox]]:h-11 [&_[role=combobox]]:whitespace-nowrap [&_[role=combobox]]:rounded-xl [&_[role=combobox]]:px-2 sm:[&_[role=combobox]]:px-4 [&_[role=combobox]]:font-medium [&_[role=combobox]]:outline-transparent"
              :class="
                morePeriod
                  ? '[&_[role=combobox]]:bg-n-solid-1 [&_[role=combobox]]:text-n-slate-12 [&_[role=combobox]]:shadow-sm'
                  : '[&_[role=combobox]]:bg-transparent [&_[role=combobox]]:text-n-slate-11 [&_[role=combobox]:hover]:text-n-slate-12'
              "
            />
          </div>
        </div>
        <div v-if="canCreate" class="flex flex-wrap items-center gap-2">
          <button
            v-if="!openAd"
            type="button"
            data-panel-create
            class="inline-flex min-h-11 items-center gap-2 rounded-xl px-4 text-sm font-520 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand focus-visible:ring-offset-2"
            :class="
              pausedCount
                ? 'border border-solid border-n-brand bg-transparent text-n-brand hover:bg-n-brand/10'
                : 'border-0 bg-n-brand text-white hover:bg-n-brand/90'
            "
            @click="startCreating('novo')"
          >
            <span class="i-lucide-plus size-4" aria-hidden="true" />
            {{ $t('CRM_KANBAN.META_ADS_HUB.CRIAR.BUTTON') }}
          </button>
          <MetaAdsReportButton
            v-if="!sample && panel"
            :period="panel.period || period"
          />
        </div>
        <MetaAdsReportButton
          v-else-if="!sample && panel"
          :period="panel.period || period"
        />
      </div>
      <p
        data-panel-period-hint
        class="m-0 flex flex-wrap items-center gap-x-2 gap-y-1 text-sm font-normal text-n-slate-11"
        aria-live="polite"
      >
        <span>{{ periodHint }}</span>
        <span
          v-if="switchingPeriod"
          data-panel-period-loading
          class="inline-flex items-center gap-1.5 text-n-slate-10"
        >
          <span
            class="i-lucide-loader-circle size-3.5 animate-spin"
            aria-hidden="true"
          />
          {{ $t('CRM_KANBAN.META_ADS_HUB.PANEL.PERIOD_LOADING') }}
        </span>
      </p>
    </div>

    <MetaAdsCreate
      v-if="showCreate"
      :kind="CREATE_KINDS[creating]"
      @back="stopCreating"
    />

    <MetaAdsAdDetail
      v-else-if="openAd"
      :key="openAd"
      :ad-id="openAd"
      :period="period"
      @back="rememberAd(null)"
    />

    <div v-else-if="loading && !panel" class="flex justify-center p-12">
      <Spinner />
    </div>

    <div
      v-else-if="panel"
      data-panel-body
      class="flex flex-col gap-5 transition-opacity duration-200"
      :class="{ 'pointer-events-none opacity-50': switchingPeriod }"
      :aria-busy="switchingPeriod"
    >
      <MetaAdsPausedAds v-if="canCreate" @count="pausedCount = $event" />
      <!-- Período sem ninguém de anúncio (painel sem gasto, #2011): uma frase e o caminho para o histórico, em vez de
           zeros que parecem defeito. Com gasto, o painel segue: o dinheiro investido sem conversa é o recado. -->
      <div
        v-if="periodEmpty"
        data-panel-period-empty
        class="flex flex-col items-start gap-4 rounded-2xl bg-n-solid-1 px-6 py-8 ring-1 ring-n-weak"
      >
        <span
          class="i-lucide-calendar-search size-8 text-n-slate-10"
          aria-hidden="true"
        />
        <div class="flex flex-col gap-1">
          <p class="m-0 text-lg font-semibold text-n-slate-12">
            {{
              $t('CRM_KANBAN.META_ADS_HUB.PANEL.PERIOD_EMPTY.TITLE', {
                when: $t(`${PERIOD_KEYS}.${period}.IN`),
              })
            }}
          </p>
          <p class="m-0 text-sm text-n-slate-11">
            {{ periodContext }}
          </p>
        </div>
        <Button
          v-if="period !== 'all'"
          data-panel-period-empty-all
          :label="$t('CRM_KANBAN.META_ADS_HUB.PANEL.PERIOD_EMPTY.SEE_ALL')"
          icon="i-lucide-history"
          class="!min-h-11 !rounded-xl"
          @click="choosePeriod('all')"
        />
      </div>
      <template v-else>
        <div
          data-panel-hero
          class="relative flex flex-col gap-4 overflow-hidden rounded-2xl bg-n-heroi px-5 py-5 text-white ring-1 ring-inset ring-white/10 dark:bg-n-heroi-escuro sm:px-7 sm:py-6"
        >
          <span
            aria-hidden="true"
            class="pointer-events-none absolute -end-16 -top-24 size-72 rounded-full border-[3rem] border-n-blue-9 opacity-15"
          />
          <p
            class="relative m-0 flex flex-wrap gap-x-3 gap-y-1 text-sm font-medium text-white/70"
            aria-live="polite"
          >
            <span>
              {{ periodContext }}
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
            class="relative m-0 max-w-3xl text-balance text-2xl font-bold leading-tight tracking-tight text-white tabular-nums sm:text-3xl"
          >
            {{ headline }}
          </h3>
          <MetaAdsDailyAction
            v-if="advice"
            :advice="advice"
            :days="panel.days || 30"
            :currency="panel.currency"
            :expanded="expandedTargets"
            :read-only="readOnly"
            @act="onAdvice"
            @changed="live.reload()"
          />
        </div>

        <!-- v-show: fechar a lista não apaga o que cada mensagem sugerida já fez (rascunho, "Enviada"). -->
        <div
          v-if="stalled.length"
          v-show="showStalled"
          data-panel-stalled
          class="flex flex-col gap-4 rounded-2xl bg-n-solid-1 p-5 ring-1 ring-inset ring-n-weak sm:p-6"
        >
          <h4 class="m-0 text-sm font-semibold text-n-slate-11">
            {{
              $t(
                'CRM_KANBAN.META_ADS_HUB.PANEL.STALLED_TITLE',
                { count: stalledCount },
                stalledCount
              )
            }}
          </h4>
          <p
            v-if="readOnly"
            data-panel-stalled-scope
            class="m-0 text-xs text-n-slate-11"
          >
            {{ $t('CRM_KANBAN.META_ADS_HUB.PANEL.LIST_SCOPE') }}
          </p>
          <ul class="flex flex-col gap-2 p-0 m-0 list-none">
            <li
              v-for="card in stalled"
              :key="card.id"
              data-panel-stalled-card
              class="flex flex-wrap items-center gap-4 rounded-xl px-4 py-3 ring-1 ring-inset ring-n-weak"
            >
              <span class="flex-1 min-w-0">
                <span
                  class="block text-sm font-semibold truncate text-n-slate-12"
                >
                  {{ card.title }}
                </span>
                <span class="block text-xs font-normal text-n-slate-10">
                  {{
                    $t('CRM_KANBAN.META_ADS_HUB.PANEL.STALLED_SINCE', {
                      time: waitingFor(card.waiting_since),
                    })
                  }}
                </span>
              </span>
              <span
                v-if="card.value != null"
                class="text-base font-semibold tabular-nums text-n-slate-12"
              >
                {{ fmt(card.value) }}
              </span>
              <router-link
                v-if="card.conversation_id"
                :to="conversationLink(card.conversation_id)"
                class="inline-flex min-h-11 items-center gap-2 rounded-xl border-0 bg-n-solid-1 px-4 text-sm font-medium text-n-slate-12 no-underline ring-1 ring-inset ring-n-weak transition hover:bg-n-alpha-1 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
              >
                {{ $t('CRM_KANBAN.META_ADS_HUB.PANEL.OPEN_CONVERSATION') }}
              </router-link>
              <MetaAdsQuoteMessage v-if="card.conversation_id" :card="card" />
            </li>
          </ul>
          <p
            v-if="stalledMore > 0"
            data-panel-stalled-more
            class="m-0 text-sm font-normal text-n-slate-11"
          >
            {{
              $t('CRM_KANBAN.META_ADS_HUB.PANEL.STALLED_MORE', {
                count: stalledMore,
              })
            }}
          </p>
        </div>

        <div
          class="flex flex-col gap-5 rounded-2xl bg-n-solid-1 p-5 ring-1 ring-inset ring-n-weak sm:p-6"
        >
          <h4 class="m-0 text-sm font-semibold text-n-slate-11">
            {{ $t('CRM_KANBAN.META_ADS_HUB.PANEL.PATH_TITLE') }}
          </h4>
          <ol
            class="m-0 grid list-none grid-cols-2 gap-2 p-0"
            :class="path.length === 3 ? 'xl:grid-cols-3' : 'xl:grid-cols-4'"
          >
            <li
              v-for="step in path"
              :key="step.key"
              :data-panel-path="step.key"
              class="relative flex min-w-0 flex-col gap-1 rounded-xl bg-n-solid-1 px-4 py-3 ring-1 ring-inset ring-n-weak has-[:focus-visible]:ring-2 has-[:focus-visible]:ring-n-brand"
              :class="[
                (PATH_LISTS[step.key] && !sample) || step.connect
                  ? 'transition hover:bg-n-alpha-1 hover:ring-n-slate-6'
                  : '',
                step.connect ? '!bg-n-blue-2 !ring-n-blue-6' : '',
              ]"
            >
              <span
                class="text-xl font-semibold tabular-nums sm:text-2xl"
                :class="step.win ? 'text-n-teal-11' : 'text-n-slate-12'"
              >
                {{ step.value }}
              </span>
              <span class="text-sm text-n-slate-11">
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
              <span v-if="step.note" class="text-xs text-n-slate-10">
                {{ step.note }}
              </span>
              <button
                v-if="step.connect"
                type="button"
                data-panel-connect
                class="mt-1 inline-flex min-h-11 items-center gap-1.5 self-start whitespace-nowrap rounded-xl border-0 bg-n-blue-9 px-3 text-sm sm:px-4 font-semibold text-white transition hover:bg-n-blue-10 focus-visible:outline-none after:absolute after:inset-0 after:rounded-xl after:content-['']"
                @click="emit('connect')"
              >
                {{ $t('CRM_KANBAN.META_ADS_HUB.PANEL.CONNECT_SPEND.CTA') }}
                <span
                  class="i-lucide-arrow-right hidden size-3.5 sm:inline-block"
                  aria-hidden="true"
                />
              </button>
              <span
                v-if="step.response"
                data-panel-response-time
                class="flex flex-col text-xs text-n-slate-10"
              >
                <span>
                  {{ $t('CRM_KANBAN.META_ADS_HUB.PANEL.RESPONSE_TIME.LABEL') }}
                  <span
                    data-panel-response-time-value
                    class="font-semibold tabular-nums"
                    :class="
                      step.response.slow ? 'text-n-amber-11' : 'text-n-slate-12'
                    "
                  >
                    {{ step.response.value }}
                  </span>
                </span>
                <span class="flex flex-wrap gap-x-1.5">
                  <span>
                    {{ $t('CRM_KANBAN.META_ADS_HUB.PANEL.RESPONSE_TIME.NOTE') }}
                  </span>
                  <span
                    v-if="step.response.unanswered"
                    data-panel-response-time-unanswered
                    class="before:content-['·'] before:me-1.5"
                  >
                    {{
                      $t(
                        'CRM_KANBAN.META_ADS_HUB.PANEL.RESPONSE_TIME.UNANSWERED',
                        { count: step.response.unanswered },
                        step.response.unanswered
                      )
                    }}
                  </span>
                </span>
              </span>
              <!-- O botão cobre a etapa inteira (after:inset-0), como no cartão de anúncio. -->
              <button
                v-if="PATH_LISTS[step.key] && !sample"
                type="button"
                :data-panel-path-open="PATH_LISTS[step.key]"
                :aria-expanded="String(openList === PATH_LISTS[step.key])"
                aria-controls="meta-ads-path-list"
                :aria-label="
                  $t('CRM_KANBAN.META_ADS_HUB.PANEL.PATH_LIST.OPEN_LABEL', {
                    step: $t(
                      `CRM_KANBAN.META_ADS_HUB.PANEL.PATH.${step.key}`,
                      2
                    ),
                  })
                "
                class="inline-flex min-h-11 items-center gap-1 self-start rounded-xl border-0 bg-transparent p-0 text-sm font-medium text-n-blue-11 focus-visible:outline-none after:absolute after:inset-0 after:rounded-xl after:content-['']"
                @click="toggleList(PATH_LISTS[step.key])"
              >
                {{
                  openList === PATH_LISTS[step.key]
                    ? $t('CRM_KANBAN.META_ADS_HUB.PANEL.PATH_LIST.CLOSE')
                    : $t('CRM_KANBAN.META_ADS_HUB.PANEL.PATH_LIST.OPEN')
                }}
                <span
                  class="size-3.5"
                  :class="
                    openList === PATH_LISTS[step.key]
                      ? 'i-lucide-chevron-up'
                      : 'i-lucide-chevron-down'
                  "
                  aria-hidden="true"
                />
              </button>
            </li>
          </ol>
          <ul class="flex flex-wrap gap-2 p-0 m-0 list-none tabular-nums">
            <li
              v-if="totals.return_per_real != null"
              class="rounded-lg bg-n-alpha-1 px-2.5 py-1 text-sm font-medium text-n-slate-12"
            >
              {{
                $t('CRM_KANBAN.META_ADS_HUB.PANEL.RETURN', {
                  value: fmt(totals.return_per_real),
                })
              }}
            </li>
            <li
              class="rounded-lg bg-n-alpha-1 px-2.5 py-1 text-sm font-medium text-n-slate-12"
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
          <MetaAdsPathList
            v-if="openList"
            id="meta-ads-path-list"
            :key="`${openList}-${listPeriod}`"
            :step="openList"
            :period="listPeriod"
            :currency="panel.currency"
          />
          <p
            v-if="openList && readOnly"
            data-panel-list-scope
            class="m-0 text-xs text-n-slate-11"
          >
            {{ $t('CRM_KANBAN.META_ADS_HUB.PANEL.LIST_SCOPE') }}
          </p>
        </div>

        <div
          class="flex flex-col gap-5 rounded-2xl bg-n-solid-1 p-5 ring-1 ring-inset ring-n-weak sm:p-6"
        >
          <h4 class="m-0 text-sm font-semibold text-n-slate-11">
            {{
              otherAds.length
                ? $t('CRM_KANBAN.META_ADS_HUB.PANEL.ADS_WHATSAPP_TITLE')
                : $t('CRM_KANBAN.META_ADS_HUB.PANEL.ADS_TITLE')
            }}
          </h4>
          <p v-if="!ads.length" class="m-0 text-sm text-n-slate-11">
            {{ $t('CRM_KANBAN.META_ADS_HUB.PANEL.ADS_EMPTY') }}
          </p>
          <ul
            v-else
            class="grid items-stretch gap-5 p-0 m-0 list-none sm:grid-cols-2 xl:grid-cols-3"
          >
            <li
              v-for="ad in ads"
              :key="ad.ad_id"
              :data-panel-ad="ad.ad_id"
              class="relative flex flex-col overflow-hidden rounded-xl bg-n-solid-1 ring-1 ring-n-weak transition hover:ring-n-slate-6 has-[:focus-visible]:ring-2 has-[:focus-visible]:ring-n-brand"
            >
              <!-- Moldura 4:5 em todos os cartões (#2010): o criativo aparece inteiro (vertical, feed ou quadrado) e a
                 sobra é a própria foto desfocada, para a linha de cartões ficar alinhada sem cortar o texto do anúncio. -->
              <div class="relative overflow-hidden aspect-[4/5] bg-n-alpha-1">
                <template v-if="imageOf(ad)">
                  <img
                    :src="imageOf(ad)"
                    alt=""
                    aria-hidden="true"
                    loading="lazy"
                    data-panel-ad-image-backdrop
                    class="absolute inset-0 object-cover scale-110 size-full blur-2xl brightness-90"
                  />
                  <img
                    :src="imageOf(ad)"
                    :alt="ad.name || ''"
                    loading="lazy"
                    data-panel-ad-image
                    class="relative block object-contain size-full"
                    @error="imageFailed(ad)"
                  />
                </template>
                <div
                  v-else
                  data-panel-ad-placeholder
                  class="grid size-full place-items-center bg-gradient-to-br"
                  :class="thumbClass(ad.ad_id)"
                >
                  <span
                    class="i-lucide-image size-8 text-white/50"
                    aria-hidden="true"
                  />
                </div>
              </div>
              <div class="flex flex-col flex-1 gap-4 p-4">
                <div
                  class="flex flex-wrap items-start justify-between gap-x-3 gap-y-2"
                >
                  <span
                    class="text-sm font-semibold leading-snug break-words text-n-slate-12 line-clamp-2"
                  >
                    {{
                      ad.name || $t('CRM_KANBAN.META_ADS_HUB.PANEL.AD_NO_NAME')
                    }}
                  </span>
                  <span
                    v-if="ad.verdict"
                    :data-verdict="ad.verdict"
                    class="inline-flex items-center rounded-md px-1.5 py-0.5 text-[11px] font-medium leading-4 flex-none whitespace-nowrap"
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
                    <dt class="text-xs text-n-slate-11">
                      {{
                        $t(`CRM_KANBAN.META_ADS_HUB.PANEL.AD_STATS.${stat.key}`)
                      }}
                    </dt>
                    <dd
                      class="m-0 whitespace-nowrap text-base font-semibold tabular-nums text-n-slate-12"
                    >
                      {{ stat.value }}
                    </dd>
                  </div>
                </dl>
                <p class="m-0 text-xs font-normal tabular-nums text-n-slate-10">
                  {{
                    ad.cost_per_sale != null
                      ? $t('CRM_KANBAN.META_ADS_HUB.PANEL.PER_SALE', {
                          value: fmt(ad.cost_per_sale),
                        })
                      : $t(
                          'CRM_KANBAN.META_ADS_HUB.PANEL.AD_QUOTES',
                          { count: openQuotesOf(ad) },
                          openQuotesOf(ad)
                        )
                  }}
                </p>
                <!-- O botão cobre o cartão inteiro (after:inset-0): tocar em qualquer parte abre o anúncio, e o
                   leitor de tela ouve um só botão com o nome dele. -->
                <button
                  v-if="!sample"
                  type="button"
                  :data-panel-ad-open="ad.ad_id"
                  :aria-label="
                    $t('CRM_KANBAN.META_ADS_HUB.PANEL.OPEN_AD_LABEL', {
                      name:
                        ad.name ||
                        $t('CRM_KANBAN.META_ADS_HUB.PANEL.AD_NO_NAME'),
                    })
                  "
                  class="inline-flex min-h-11 mt-auto items-center gap-1 self-start rounded-xl border-0 bg-transparent p-0 text-sm font-medium text-n-blue-11 focus-visible:outline-none after:absolute after:inset-0 after:rounded-xl after:content-['']"
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

        <div
          v-if="otherAds.length"
          data-panel-other-ads
          class="flex flex-col gap-4 rounded-2xl bg-n-solid-1 p-5 ring-1 ring-inset ring-n-weak sm:p-6"
        >
          <div
            class="flex flex-wrap items-baseline justify-between gap-x-4 gap-y-1"
          >
            <h4 class="m-0 text-sm font-semibold text-n-slate-11">
              {{ $t('CRM_KANBAN.META_ADS_HUB.PANEL.OTHER_ADS.TITLE') }}
            </h4>
            <span class="text-sm font-semibold tabular-nums text-n-slate-12">
              {{
                $t('CRM_KANBAN.META_ADS_HUB.PANEL.OTHER_ADS.TOTAL', {
                  value: fmt(totals.other_spend),
                })
              }}
            </span>
          </div>
          <p class="m-0 max-w-3xl text-sm text-n-slate-11">
            {{ $t('CRM_KANBAN.META_ADS_HUB.PANEL.OTHER_ADS.HINT') }}
          </p>
          <ul class="m-0 flex list-none flex-col gap-2 p-0">
            <li
              v-for="ad in otherAds"
              :key="ad.ad_id"
              :data-panel-other-ad="ad.ad_id"
              class="flex flex-wrap items-center gap-x-4 gap-y-2 rounded-xl px-3 py-3 ring-1 ring-inset ring-n-weak"
            >
              <span
                class="relative size-12 flex-none overflow-hidden rounded-lg bg-n-alpha-1"
              >
                <img
                  v-if="imageOf(ad)"
                  :src="imageOf(ad)"
                  alt=""
                  loading="lazy"
                  class="size-full object-cover"
                  @error="imageFailed(ad)"
                />
                <span
                  v-else
                  class="grid size-full place-items-center bg-gradient-to-br"
                  :class="thumbClass(ad.ad_id)"
                >
                  <span
                    class="i-lucide-image size-5 text-white/50"
                    aria-hidden="true"
                  />
                </span>
              </span>
              <span
                class="min-w-0 flex-1 basis-40 text-sm font-semibold text-n-slate-12 line-clamp-2"
              >
                {{ ad.name || $t('CRM_KANBAN.META_ADS_HUB.PANEL.AD_NO_NAME') }}
              </span>
              <dl
                class="m-0 grid grid-cols-3 gap-x-5 text-end tabular-nums sm:w-auto"
              >
                <div
                  v-for="stat in ['SPEND', 'CLICKS', 'SHOWN']"
                  :key="stat"
                  class="flex flex-col gap-0.5"
                >
                  <dt class="text-xs text-n-slate-11">
                    {{ $t(`CRM_KANBAN.META_ADS_HUB.PANEL.OTHER_ADS.${stat}`) }}
                  </dt>
                  <dd
                    class="m-0 whitespace-nowrap text-sm font-semibold text-n-slate-12"
                  >
                    {{
                      stat === 'SPEND'
                        ? fmt(ad.spend)
                        : number(
                            stat === 'CLICKS' ? ad.link_clicks : ad.impressions
                          )
                    }}
                  </dd>
                </div>
              </dl>
            </li>
          </ul>
        </div>

        <MetaAdsConfidence
          v-if="panel.confidence"
          :confidence="panel.confidence"
          :comparison="panel.meta_comparison || null"
          :can-fix="!readOnly"
          @fix="emit('open', 3)"
        />
      </template>
    </div>
  </section>
</template>
