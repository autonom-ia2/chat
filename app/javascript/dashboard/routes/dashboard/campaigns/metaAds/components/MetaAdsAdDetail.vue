<script setup>
import { computed, nextTick, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute } from 'vue-router';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import CrmMetaAdsConnectionAPI from 'dashboard/api/crmMetaAdsConnection';
import { useMapGetter } from 'dashboard/composables/store';
import { fusoDaConta } from 'dashboard/helper/fusoDaConta';
import { conversationUrl, frontendURL } from 'dashboard/helper/URLHelper';
import {
  SITUATION_CLASSES,
  dayMonth,
  situation,
} from '../semLogin/anunciosSemLogin';
import {
  VERDICT_CLASSES,
  adImage,
  amount,
  intlLocale,
  periodRange,
  relativeTime,
  thumbClass,
} from '../metaAdsHelpers';
import { useMetaAdsLive } from '../useMetaAdsLive';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import { usePermissionGranted } from 'dashboard/composables/useCanManage';
import { lerGestao } from '../gestaoDoAnuncio';
import MetaAdsComments from './comentarios/MetaAdsComments.vue';
import CuidarAnuncioEntrada from '../comentariosIa/CuidarAnuncioEntrada.vue';
import comentariosInstagram from './comentarios/comentariosInstagram';
import comentariosFacebook from './comentarios/comentariosFacebook';
import MetaAdsAdStatus from './MetaAdsAdStatus.vue';
import MetaAdsAdPost from './MetaAdsAdPost.vue';
import MetaAdsBudget from './MetaAdsBudget.vue';
import { lerOrcamento } from '../criacaoNaMeta';

// Anúncios da Meta (#1088, F3b): o anúncio por dentro, passos 3 e 4 da jornada "O painel do dia a dia". A
// imagem no formato dela, o veredito com o porquê em números, o custo por venda ao lado da média da conta, o
// gasto e as conversas de cada dia e as propostas que vieram dele. Os números e o veredito vêm prontos do
// servidor (GET panel_ad, só banco); a tela só formata. Fica viva como o painel (useMetaAdsLive).
//
// Sem conexão (Anúncios sem login, #1960, `spend` nil): sem gasto, veredito e porquê; o gráfico é só de conversas
// e, no lugar das propostas, a lista de quem veio do anúncio (`people`), com a situação de cada um.
const props = defineProps({
  adId: { type: String, required: true },
  period: { type: String, required: true },
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

// "Este mês · 1 – 21 de out.": o nome do período e as datas que o servidor devolveu (#2011).
const periodContext = computed(() => {
  const name = t(
    `CRM_KANBAN.META_ADS_HUB.PANEL.PERIODS.${ad.value?.period || props.period}.NAME`
  );
  const range = periodRange(ad.value?.from, ad.value?.to, locale.value);
  return range
    ? t('CRM_KANBAN.META_ADS_HUB.PANEL.PERIOD_CTX', { name, range })
    : name;
});

const isCurrent = asked =>
  asked.adId === props.adId && asked.period === props.period;

const live = useMetaAdsLive({
  // Trocar de anúncio ou de período no meio de uma leitura: a resposta antiga é descartada.
  load: async () => {
    const asked = { adId: props.adId, period: props.period };
    let data;
    try {
      ({ data } = await CrmMetaAdsConnectionAPI.panelAd(
        asked.adId,
        asked.period
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

watch(() => [props.adId, props.period], retry);

const fmt = value => amount(value, ad.value?.currency, locale.value);

const withoutSpend = computed(() => ad.value?.spend == null);

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
      ...(withoutSpend.value ? [] : [makeTile('SPEND', fmt(data.spend))]),
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

const people = computed(() => ad.value?.people || []);
const currentAccountId = useMapGetter('getCurrentAccountId');
const getAccount = useMapGetter('accounts/getAccount');
const timeZone = computed(() =>
  fusoDaConta(getAccount.value?.(currentAccountId.value))
);
const personDay = person =>
  dayMonth(person.touched_at, timeZone.value, locale.value);
const SEM_LOGIN_AD = 'CRM_KANBAN.META_ADS_HUB.SEM_LOGIN.AD';
const situationText = person => {
  const key = situation(person);
  if (key !== 'BOUGHT') return t(`${SEM_LOGIN_AD}.STATUS.${key}`);
  return person.value != null
    ? t(`${SEM_LOGIN_AD}.STATUS.BOUGHT`, { value: fmt(person.value) })
    : t(`${SEM_LOGIN_AD}.STATUS.BOUGHT_NO_VALUE`);
};

const conversationLink = id =>
  frontendURL(conversationUrl({ accountId: route.params.accountId, id }));

const waitingFor = value => relativeTime(value, locale.value);

// Gráfico do período: uma barra de gasto por dia e um ponto por dia com conversa (sem gasto, a barra é a conversa). Cada série tem a própria
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
    const talks = day.conversations || 0;
    const bar = withoutSpend.value
      ? { value: talks, max: maxTalks }
      : { value: spend, max: maxSpend };
    const height = bar.max ? (bar.value / bar.max) * room : 0;
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
      dot:
        talks && !withoutSpend.value
          ? CHART.height - (talks / maxTalks) * room
          : null,
      title: t(
        withoutSpend.value
          ? 'CRM_KANBAN.META_ADS_HUB.AD_DETAIL.CHART_DAY_TALKS'
          : 'CRM_KANBAN.META_ADS_HUB.AD_DETAIL.CHART_DAY',
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

// Gestão mínima (#2161, flag meta_ads_gestao): situação do anúncio, botão de pausar e o post da Página. Só com
// conexão (sem login não há token para ler nem mudar o anúncio).
const isFeatureEnabledonAccount = useMapGetter(
  'accounts/isFeatureEnabledonAccount'
);
const gestaoOn = computed(() =>
  isFeatureEnabledonAccount.value(
    Number(route.params.accountId),
    FEATURE_FLAGS.META_ADS_GESTAO
  )
);
const canManage = usePermissionGranted('meta_ads_manage');
const loginPermissions = Object.fromEntries(
  comentariosInstagram.PERMISSOES_PARA_ENTRAR.map(key => [
    key,
    usePermissionGranted(key),
  ])
);
// Conectar a Página como caixa do Messenger, quando a conta não tem (comentários do Facebook, #2359).
const canCreateInbox = loginPermissions.inbox_manage;

// Comentários do anúncio, uma aba por rede, cada uma atrás da própria flag: Instagram (#2196) e Facebook (#2197).
// Sem nenhuma aba ligada, a seção não aparece.
// O botão de entrar no Instagram segue as permissões do caminho (comentariosInstagram.podeEntrar, #2358). O do
// Facebook leva à Conexão, que já é de quem gere os anúncios, ou a conectar a caixa da Página (canCreateInbox, #2359).
const COMMENT_TABS = [
  {
    key: 'INSTAGRAM',
    flag: FEATURE_FLAGS.META_ADS_COMENTARIOS_INSTAGRAM,
    adaptador: comentariosInstagram,
    podeEntrar: status =>
      comentariosInstagram.podeEntrar(
        status,
        key => loginPermissions[key].value
      ),
  },
  {
    key: 'FACEBOOK',
    flag: FEATURE_FLAGS.META_ADS_COMENTARIOS_FACEBOOK,
    adaptador: comentariosFacebook,
  },
];
const commentTabs = computed(() =>
  COMMENT_TABS.filter(tab =>
    isFeatureEnabledonAccount.value(Number(route.params.accountId), tab.flag)
  )
);
const gestao = ref(null);

// Comentários só com conexão, que é quem tem token para ler na Meta (#2196). O sinal é a gestão, que leu o anúncio
// ao vivo agora, ou o gasto, que só vem de anúncio sincronizado por uma conexão (sem login, #1960, ele é nil). A
// gestão sozinha não basta: uma falha passageira na leitura dela tiraria os comentários de um anúncio com números. O
// gasto sozinho também não: anúncio que nunca rodou, ou parou antes do período, não tem número nenhum (#2335).
const showComments = computed(
  () =>
    gestaoOn.value &&
    commentTabs.value.length > 0 &&
    Boolean(gestao.value || (ad.value && !withoutSpend.value))
);

// IA cuida dos comentários (#2212, B2, flag meta_ads_comentarios_ia): a entrada fica onde os comentários ficam.
const showCare = computed(
  () =>
    showComments.value &&
    isFeatureEnabledonAccount.value(
      Number(route.params.accountId),
      FEATURE_FLAGS.META_ADS_COMENTARIOS_IA
    )
);

const loadGestao = async () => {
  gestao.value = null;
  if (!gestaoOn.value) return;
  const asked = props.adId;
  const data = await lerGestao(asked);
  if (asked === props.adId) gestao.value = data;
};

// Orçamento e datas (#2198, flag meta_ads_criar): de quem guarda o dinheiro (grupo ou campanha). `budgetState`: ''
// (flag desligada), 'loading', 'failed' ou 'ok'. Sem orçamento o cartão some e o "Ativar" espera; na falha, diz e
// deixa tentar de novo.
const budgetOn = computed(() =>
  isFeatureEnabledonAccount.value(
    Number(route.params.accountId),
    FEATURE_FLAGS.META_ADS_CRIAR
  )
);
const budget = ref(null);
const budgetState = ref('');
const loadBudget = async () => {
  budget.value = null;
  budgetState.value = '';
  if (!budgetOn.value) return;
  budgetState.value = 'loading';
  const asked = props.adId;
  try {
    const data = await lerOrcamento(asked);
    if (asked !== props.adId) return;
    budget.value = data;
    budgetState.value = data ? 'ok' : 'failed';
  } catch {
    if (asked === props.adId) budgetState.value = 'failed';
  }
};
watch(() => props.adId, loadBudget);

watch(() => props.adId, loadGestao);

// A entrega (`effective_status`) é a Meta quem diz: depois de mudar, a situação é lida de novo, sem tirar o selo.
const statusChanged = async status => {
  gestao.value = { ...gestao.value, status };
  const asked = props.adId;
  const data = await lerGestao(asked);
  if (data && asked === props.adId) gestao.value = data;
};

onMounted(() => {
  live.start();
  loadGestao();
  loadBudget();
});

// Link de imagem da Meta vencido: mostra o quadro de reserva (guarda a URL que falhou, então um link novo volta
// a tentar).
const brokenImages = ref([]);
const image = computed(() => adImage(ad.value, brokenImages.value));
</script>

<template>
  <section data-ad-detail class="flex flex-col gap-5">
    <button
      type="button"
      data-ad-detail-back
      class="inline-flex min-h-11 items-center gap-2 rounded-xl border-0 bg-n-solid-1 px-4 text-sm font-medium text-n-slate-12 no-underline ring-1 ring-inset ring-n-weak transition hover:bg-n-alpha-1 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand self-start"
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
      class="flex flex-wrap items-center justify-between gap-3 rounded-2xl bg-n-solid-1 p-6 ring-1 ring-inset ring-n-weak"
    >
      <p class="m-0 text-sm text-n-slate-11">
        {{ $t('CRM_KANBAN.META_ADS_HUB.AD_DETAIL.ERROR') }}
      </p>
      <button
        type="button"
        data-ad-detail-retry
        class="inline-flex min-h-11 items-center gap-2 rounded-xl border-0 bg-n-solid-1 px-4 text-sm font-medium text-n-slate-12 no-underline ring-1 ring-inset ring-n-weak transition hover:bg-n-alpha-1 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
        @click="retry"
      >
        {{ $t('CRM_KANBAN.META_ADS_HUB.AD_DETAIL.RETRY') }}
      </button>
    </div>

    <!-- Sem números no período (nunca rodou, ou parou antes): o aviso fica, e o que a conexão lê ao vivo na Meta
    (situação, orçamento, post e comentários) continua aqui (#2335). -->
    <template v-else-if="!ad">
      <p
        data-ad-detail-empty
        class="m-0 rounded-2xl bg-n-solid-1 p-6 text-sm text-n-slate-11 ring-1 ring-inset ring-n-weak"
      >
        {{ $t('CRM_KANBAN.META_ADS_HUB.AD_DETAIL.EMPTY') }}
      </p>
      <div
        v-if="gestao"
        data-ad-detail-gestao
        class="rounded-2xl bg-n-solid-1 p-5 ring-1 ring-inset ring-n-weak sm:p-6"
      >
        <MetaAdsAdStatus
          :ad-id="adId"
          :ad-name="gestao.name || ''"
          :gestao="gestao"
          :can-manage="canManage"
          :budget="budget"
          :budget-state="budgetState"
          tone="light"
          @retry-budget="loadBudget"
          @changed="statusChanged"
        />
      </div>
      <MetaAdsBudget
        v-if="budget"
        :ad-id="adId"
        :budget="budget"
        :can-manage="canManage"
        @changed="budget = $event"
      />
      <MetaAdsAdPost v-if="gestao?.post" :post="gestao.post" />
      <CuidarAnuncioEntrada
        v-if="showCare"
        :ad-id="adId"
        :can-manage="canManage"
      />
      <MetaAdsComments
        v-if="showComments"
        :ad-id="adId"
        :abas="commentTabs"
        :can-manage="canManage"
        :can-create-inbox="canCreateInbox"
      />
    </template>

    <template v-else>
      <header
        data-ad-detail-hero
        class="relative flex flex-col gap-2 overflow-hidden rounded-2xl bg-n-heroi px-5 py-5 text-white ring-1 ring-inset ring-white/10 dark:bg-n-heroi-escuro sm:px-7 sm:py-6"
      >
        <span
          aria-hidden="true"
          class="pointer-events-none absolute -end-16 -top-24 size-72 rounded-full border-[3rem] border-n-blue-9 opacity-15"
        />
        <p class="relative m-0 text-sm font-medium text-white/70">
          {{ periodContext }}
        </p>
        <h3
          ref="heading"
          tabindex="-1"
          data-ad-detail-name
          class="relative m-0 text-balance text-2xl font-bold leading-tight tracking-tight text-white focus:outline-none sm:text-3xl"
        >
          {{ ad.name || $t('CRM_KANBAN.META_ADS_HUB.PANEL.AD_NO_NAME') }}
        </h3>
        <p
          v-if="context.length"
          data-ad-detail-context
          class="relative m-0 flex flex-wrap items-baseline gap-x-5 gap-y-1 text-base text-white/80"
        >
          <span
            v-for="part in context"
            :key="part.key"
            class="inline-flex items-baseline min-w-0 gap-1.5"
          >
            <span class="text-sm font-medium text-white/70">
              {{ $t(`CRM_KANBAN.META_ADS_HUB.AD_DETAIL.${part.key}`) }}
            </span>
            <span class="min-w-0">{{ part.name }}</span>
          </span>
        </p>
        <MetaAdsAdStatus
          v-if="gestao"
          :ad-id="adId"
          :ad-name="ad.name || ''"
          :gestao="gestao"
          :can-manage="canManage"
          :budget="budget"
          :budget-state="budgetState"
          @retry-budget="loadBudget"
          @changed="statusChanged"
        />
      </header>

      <div
        class="grid items-start gap-5 lg:grid-cols-[minmax(0,2fr)_minmax(0,3fr)]"
      >
        <div class="flex flex-col gap-5">
          <figure
            class="m-0 flex flex-col gap-2 overflow-hidden rounded-2xl bg-n-solid-1 ring-1 ring-n-weak"
          >
            <div class="flex justify-center bg-n-alpha-1">
              <img
                v-if="image"
                :src="image"
                :alt="ad.name || ''"
                data-ad-detail-image
                class="block object-contain w-full h-auto max-h-[40rem]"
                @error="brokenImages = [...brokenImages, image]"
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
                class="inline-flex min-h-11 items-center gap-1.5 rounded-xl text-sm font-medium text-n-blue-11 no-underline hover:underline focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
              >
                {{ $t('CRM_KANBAN.META_ADS_HUB.AD_DETAIL.PREVIEW') }}
                <span
                  class="i-lucide-external-link size-3.5"
                  aria-hidden="true"
                />
              </a>
            </figcaption>
          </figure>
          <MetaAdsAdPost v-if="gestao?.post" :post="gestao.post" />
        </div>

        <div class="flex flex-col gap-5">
          <!-- Orçamento e datas (#2198) no topo: é o que a pessoa muda depois de ver o resultado. -->
          <MetaAdsBudget
            v-if="budget"
            :ad-id="adId"
            :budget="budget"
            :can-manage="canManage"
            @changed="budget = $event"
          />
          <span
            v-if="ad.verdict"
            :data-verdict="ad.verdict"
            class="inline-flex items-center rounded-md px-1.5 py-0.5 text-[11px] font-medium leading-4 self-start"
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
              class="flex min-w-0 flex-col gap-1 rounded-xl bg-n-solid-1 px-4 py-3 ring-1 ring-inset ring-n-weak"
            >
              <dt class="text-sm text-n-slate-11">
                {{ $t(`CRM_KANBAN.META_ADS_HUB.AD_DETAIL.TILES.${tile.key}`) }}
              </dt>
              <!-- mt-auto: rótulo que quebra em duas linhas não tira o número da linha dos outros. -->
              <dd
                class="m-0 mt-auto truncate text-xl font-semibold tabular-nums sm:text-2xl"
                :class="tile.tone"
              >
                {{ tile.value }}
              </dd>
            </div>
          </dl>

          <div
            v-if="!withoutSpend"
            data-ad-detail-why
            :data-reason="reason.kind"
            class="flex flex-col gap-2 rounded-2xl bg-n-solid-1 p-5 ring-1 ring-inset ring-n-weak"
          >
            <h4 class="m-0 text-sm font-semibold text-n-slate-11">
              {{ $t('CRM_KANBAN.META_ADS_HUB.AD_DETAIL.WHY_TITLE') }}
            </h4>
            <p
              class="m-0 text-pretty text-base leading-relaxed text-n-slate-12"
            >
              {{ reasonText }}
            </p>
            <div
              v-if="reason.kind === 'early' && openQuotes"
              data-ad-detail-meanwhile
              class="flex flex-col gap-1 pt-3 mt-1 border-0 border-t border-solid border-n-weak"
            >
              <span class="text-sm font-semibold text-n-slate-11">
                {{ $t('CRM_KANBAN.META_ADS_HUB.AD_DETAIL.MEANWHILE_TITLE') }}
              </span>
              <span class="text-sm leading-relaxed text-n-slate-12">
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
                class="inline-flex min-h-11 items-center gap-1 self-start rounded-xl border-0 bg-transparent p-0 text-sm font-medium text-n-blue-11 hover:underline focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
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
        class="flex flex-col gap-4 rounded-2xl bg-n-solid-1 p-5 ring-1 ring-inset ring-n-weak sm:p-6"
      >
        <div class="flex flex-wrap items-center justify-between gap-3">
          <h4 class="m-0 text-sm font-semibold text-n-slate-11">
            {{
              withoutSpend
                ? $t('CRM_KANBAN.META_ADS_HUB.AD_DETAIL.CHART_TITLE_TALKS')
                : $t('CRM_KANBAN.META_ADS_HUB.AD_DETAIL.CHART_TITLE')
            }}
          </h4>
          <ul
            class="m-0 flex list-none gap-4 p-0 text-xs font-medium text-n-slate-11"
          >
            <li v-if="!withoutSpend" class="flex items-center gap-1.5">
              <span
                class="rounded-sm size-2.5 bg-n-blue-8"
                aria-hidden="true"
              />
              {{ $t('CRM_KANBAN.META_ADS_HUB.AD_DETAIL.LEGEND_SPEND') }}
            </li>
            <li v-else class="flex items-center gap-1.5">
              <span
                class="rounded-sm size-2.5 bg-n-blue-8"
                aria-hidden="true"
              />
              {{ $t('CRM_KANBAN.META_ADS_HUB.AD_DETAIL.LEGEND_CONVERSATIONS') }}
            </li>
            <li v-if="!withoutSpend" class="flex items-center gap-1.5">
              <span
                class="rounded-full size-2.5 bg-n-teal-10"
                aria-hidden="true"
              />
              {{ $t('CRM_KANBAN.META_ADS_HUB.AD_DETAIL.LEGEND_CONVERSATIONS') }}
            </li>
          </ul>
        </div>
        <p
          v-if="!withoutSpend"
          data-ad-detail-chart-scale
          class="m-0 text-xs tabular-nums text-n-slate-11"
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
          class="m-0 flex justify-between text-xs tabular-nums text-n-slate-10"
          aria-hidden="true"
        >
          <span v-for="label in axis" :key="label">{{ label }}</span>
        </p>
        <details data-ad-detail-days class="group">
          <summary
            class="inline-flex min-h-11 cursor-pointer list-none items-center gap-1.5 rounded-xl text-sm font-medium text-n-blue-11 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand [&::-webkit-details-marker]:hidden"
          >
            {{ $t('CRM_KANBAN.META_ADS_HUB.AD_DETAIL.DAYS_TOGGLE') }}
            <span
              class="i-lucide-chevron-down size-3.5 group-open:rotate-180"
              aria-hidden="true"
            />
          </summary>
          <table
            class="w-full border-collapse text-sm font-normal tabular-nums"
          >
            <thead>
              <tr class="text-xs text-n-slate-11">
                <th scope="col" class="py-2 font-medium text-start">
                  {{ $t('CRM_KANBAN.META_ADS_HUB.AD_DETAIL.DAYS_DATE') }}
                </th>
                <th
                  v-if="!withoutSpend"
                  scope="col"
                  class="py-2 font-medium text-end"
                >
                  {{ $t('CRM_KANBAN.META_ADS_HUB.AD_DETAIL.LEGEND_SPEND') }}
                </th>
                <th scope="col" class="py-2 font-medium text-end">
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
                <th scope="row" class="py-2 font-normal text-start">
                  {{ day.label }}
                </th>
                <td v-if="!withoutSpend" class="py-2 text-end">
                  {{ day.spend }}
                </td>
                <td class="py-2 text-end">{{ day.talks }}</td>
              </tr>
            </tbody>
          </table>
        </details>
      </div>

      <CuidarAnuncioEntrada
        v-if="showCare"
        :ad-id="adId"
        :can-manage="canManage"
      />
      <MetaAdsComments
        v-if="showComments"
        :ad-id="adId"
        :abas="commentTabs"
        :can-manage="canManage"
        :can-create-inbox="canCreateInbox"
      />

      <div
        v-if="withoutSpend"
        data-ad-detail-people
        class="flex flex-col gap-4 rounded-2xl bg-n-solid-1 p-5 ring-1 ring-inset ring-n-weak sm:p-6"
      >
        <h4 class="m-0 text-sm font-semibold text-n-slate-11">
          {{ $t(`${SEM_LOGIN_AD}.PEOPLE`) }}
        </h4>
        <p v-if="!people.length" class="m-0 text-sm text-n-slate-11">
          {{ $t(`${SEM_LOGIN_AD}.EMPTY`) }}
        </p>
        <ul v-else class="flex flex-col gap-2 p-0 m-0 list-none">
          <li
            v-for="person in people"
            :key="person.conversation_id"
            data-ad-detail-person
            :data-situation="situation(person)"
            class="flex flex-wrap items-center gap-4 rounded-xl px-4 py-3 ring-1 ring-inset ring-n-weak"
          >
            <span class="min-w-0 basis-full sm:basis-0 sm:flex-1">
              <span
                class="block text-sm font-semibold truncate text-n-slate-12"
              >
                {{
                  person.title ||
                  $t('CRM_KANBAN.META_ADS_HUB.SEM_LOGIN.NO_NAME')
                }}
              </span>
              <span
                class="flex flex-wrap items-center gap-x-2 gap-y-1 text-xs text-n-slate-10"
              >
                <span v-if="personDay(person)">{{ personDay(person) }}</span>
                <span v-if="person.stage_name">{{ person.stage_name }}</span>
                <span
                  data-ad-detail-situation
                  class="inline-flex items-center rounded-md px-1.5 py-0.5 text-[11px] font-medium leading-4"
                  :class="SITUATION_CLASSES[situation(person)]"
                >
                  {{ situationText(person) }}
                </span>
              </span>
            </span>
            <router-link
              v-if="person.conversation_id"
              :to="conversationLink(person.conversation_id)"
              class="inline-flex min-h-11 items-center gap-2 rounded-xl border-0 bg-n-solid-1 px-4 text-sm font-medium text-n-slate-12 no-underline ring-1 ring-inset ring-n-weak transition hover:bg-n-alpha-1 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
            >
              {{ $t('CRM_KANBAN.META_ADS_HUB.PANEL.OPEN_CONVERSATION') }}
            </router-link>
          </li>
        </ul>
      </div>

      <div
        v-else
        data-ad-detail-quotes
        class="flex flex-col gap-4 rounded-2xl bg-n-solid-1 p-5 ring-1 ring-inset ring-n-weak sm:p-6"
      >
        <h4
          ref="quotesHeading"
          tabindex="-1"
          class="m-0 text-sm font-semibold text-n-slate-11 scroll-mt-4 focus:outline-none"
        >
          {{ $t('CRM_KANBAN.META_ADS_HUB.AD_DETAIL.QUOTES_TITLE') }}
        </h4>
        <p v-if="!quotes.length" class="m-0 text-sm text-n-slate-11">
          {{ $t('CRM_KANBAN.META_ADS_HUB.AD_DETAIL.QUOTES_EMPTY') }}
        </p>
        <ul v-else class="flex flex-col gap-2 p-0 m-0 list-none">
          <li
            v-for="card in quotes"
            :key="card.card_id"
            :data-ad-detail-quote="card.card_id"
            class="flex flex-wrap items-center gap-4 rounded-xl px-4 py-3 ring-1 ring-inset ring-n-weak"
          >
            <!-- No celular o título ocupa a linha toda e o valor e o botão descem; a partir de sm, dividem a linha. -->
            <span class="min-w-0 basis-full sm:basis-0 sm:flex-1">
              <span
                class="block text-sm font-semibold truncate text-n-slate-12"
              >
                {{ card.title }}
              </span>
              <span
                class="flex flex-wrap items-center gap-x-2 gap-y-1 text-xs text-n-slate-10"
              >
                <span v-if="card.stage_name">{{ card.stage_name }}</span>
                <span
                  v-if="card.status === 'won'"
                  data-ad-detail-quote-won
                  class="inline-flex items-center rounded-md px-1.5 py-0.5 text-[11px] font-medium leading-4 bg-n-teal-3 text-n-teal-11"
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
          </li>
        </ul>
      </div>
    </template>
  </section>
</template>
