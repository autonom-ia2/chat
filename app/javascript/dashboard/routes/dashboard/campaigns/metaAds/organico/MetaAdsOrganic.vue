<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { frontendURL } from 'dashboard/helper/URLHelper';
import { useAlert } from 'dashboard/composables';
import { usePermissionGranted } from 'dashboard/composables/useCanManage';
import { useFacebookPageConnect } from 'dashboard/composables/useFacebookPageConnect';
import CrmMetaAdsConnectionAPI from 'dashboard/api/crmMetaAdsConnection';
import FBChannel from 'dashboard/api/channel/fbChannel';
import instagramClient from 'dashboard/api/channel/instagramClient';
import Button from 'dashboard/components-next/button/Button.vue';
import {
  ROLLING_PERIODS,
  intlLocale,
  periodRange,
  rollingDays,
} from '../metaAdsHelpers';
import OrganicSourceCard from './OrganicSourceCard.vue';

// Anúncios da Meta › Seus posts (#2199): o que os posts da Página do Facebook e do Instagram alcançam, ao lado da aba
// Resultado (o que é pago). Responde "postar está trazendo cliente?": quem viu, quanto foi sem pagar, quem mandou
// mensagem por ali e qual post funcionou, comparado com o período anterior. Período no endereço (?periodo=).
//
// Os números vêm de GET meta_ads_connection/organico (Crm::MetaAds::Organico::Tela): a Meta lida com read_insights
// (Página) e instagram_business_manage_insights (login do Instagram), e as conversas da caixa de cada um no Chat2You.
defineProps({
  readOnly: { type: Boolean, default: false },
});

const { t, locale } = useI18n();
const route = useRoute();
const router = useRouter();
const BEST_POST_CHARS = 90;
const SENTENCE_ENDS = ['. ', '? ', '! '];
// Corte na frase só quando sobra uma citação de verdade ("Oi!" sozinho não diz qual foi o post).
const MIN_SENTENCE_CHARS = 40;

const period = ref(
  ROLLING_PERIODS.includes(route.query.periodo) ? route.query.periodo : '30d'
);
const choosePeriod = value => {
  period.value = value;
  router.replace({ query: { ...route.query, periodo: value } });
};
const days = computed(() => rollingDays(period.value));

// Textos por período e por lugar com a chave escrita inteira: a checagem de i18n confere cada uma.
const periodLabels = computed(() => ({
  '7d': t('META_ADS_ORGANIC.PERIODS.7d'),
  '30d': t('META_ADS_ORGANIC.PERIODS.30d'),
  '90d': t('META_ADS_ORGANIC.PERIODS.90d'),
}));
const seeConversationsLabels = computed(() => ({
  page: t('META_ADS_ORGANIC.SOURCE.PAGE.SEE_CONVERSATIONS'),
  instagram: t('META_ADS_ORGANIC.SOURCE.INSTAGRAM.SEE_CONVERSATIONS'),
}));

const data = ref(null);
const loading = ref(true);
const failed = ref(false);
// Trocar 7 → 90 dias rápido: só a última leitura pedida vale, a anterior que chegar depois é descartada.
let lastRequest = 0;
const load = async () => {
  lastRequest += 1;
  const request = lastRequest;
  loading.value = true;
  failed.value = false;
  try {
    const { data: result } = await CrmMetaAdsConnectionAPI.organico(days.value);
    if (request === lastRequest) data.value = result;
  } catch {
    if (request === lastRequest) failed.value = true;
  } finally {
    if (request === lastRequest) loading.value = false;
  }
};
watch(days, load, { immediate: true });

const page = computed(() => data.value?.page);
const instagram = computed(() => data.value?.instagram);
const isReady = place => place?.status === 'ok';
const anyReady = computed(
  () => isReady(page.value) || isReady(instagram.value)
);

const format = value =>
  new Intl.NumberFormat(intlLocale(locale.value)).format(value);

// Vezes que os posts apareceram sem anúncio (o servidor já tira o anúncio das duas), na Página e no Instagram lado a
// lado, nunca somadas. Não é "quem viu": no Instagram a Meta não deduplica quem viu entre tipos de post, e na Página o
// "quem viu" pode incluir o pago.
const organicViews = place => (isReady(place) ? (place.views ?? null) : null);
// Lugar ligado cujas vezes a Meta não mandou: não dá para dizer que ninguém viu os posts dele.
const viewsUnknown = computed(() =>
  [page.value, instagram.value].some(
    place => isReady(place) && organicViews(place) === null
  )
);
// Nenhum lugar com números e algum com a Meta fora: "Libere o acesso" seria falso.
const anyUnavailable = computed(() =>
  [page.value, instagram.value].some(place => place?.status === 'unavailable')
);
const headline = computed(() => {
  if (!anyReady.value)
    return anyUnavailable.value
      ? t('META_ADS_ORGANIC.HEADLINE.UNAVAILABLE')
      : t('META_ADS_ORGANIC.HEADLINE.NONE');
  const pageViews = organicViews(page.value);
  const instagramViews = organicViews(instagram.value);
  // As vezes que a Meta não mandou (null) não viram "não apareceram".
  if (pageViews === null && instagramViews === null)
    return t('META_ADS_ORGANIC.HEADLINE.UNAVAILABLE');
  if (!pageViews && !instagramViews && !viewsUnknown.value)
    return t('META_ADS_ORGANIC.HEADLINE.ZERO', { days: days.value });
  if (pageViews && instagramViews)
    return t('META_ADS_ORGANIC.HEADLINE.BOTH', {
      page: format(pageViews),
      instagram: format(instagramViews),
    });
  // Um lugar só com número: o que apareceu, ou o único que a Meta mandou (mesmo 0).
  const onPage =
    instagramViews === null || (pageViews !== null && pageViews > 0);
  return onPage
    ? t('META_ADS_ORGANIC.HEADLINE.PAGE', { count: format(pageViews) })
    : t('META_ADS_ORGANIC.HEADLINE.INSTAGRAM', {
        count: format(instagramViews),
      });
});

// Até 90 caracteres, o post inteiro. Mais longo: até o fim da última frase que cabe, se ela tiver 40 caracteres ou
// mais; senão, até a última palavra.
const shorten = text => {
  if (text.length <= BEST_POST_CHARS) return text;
  const cut = text.slice(0, BEST_POST_CHARS);
  const sentenceEnd = Math.max(
    ...SENTENCE_ENDS.map(mark => cut.lastIndexOf(mark))
  );
  if (sentenceEnd >= MIN_SENTENCE_CHARS) return cut.slice(0, sentenceEnd + 1);
  const wordEnd = cut.lastIndexOf(' ');
  return `${wordEnd > 0 ? cut.slice(0, wordEnd) : cut}…`;
};

// O post com mais curtidas e comentários dos dois lugares, e onde ele saiu.
const PLACES = { page: 'Facebook', instagram: 'Instagram' };
const bestPost = computed(() => {
  const posts = Object.entries({ page: page.value, instagram: instagram.value })
    .filter(([, place]) => isReady(place))
    .flatMap(([source, place]) =>
      (place.top_posts || []).map(post => ({ ...post, source }))
    );
  if (!posts.length) return null;
  const best = posts.reduce((top, post) =>
    post.interactions > top.interactions ? post : top
  );
  return { text: shorten(best.text), place: PLACES[best.source] };
});

// "Ver conversas": a caixa abre em "Todas" (?aba=todas), para a pessoa ver a lista inteira, não só as dela.
const openConversations = inboxId =>
  router.push({
    path: frontendURL(`accounts/${route.params.accountId}/inbox/${inboxId}`),
    query: { aba: 'todas' },
  });

// O botão do topo, a ação principal da tela: as conversas do lugar com mais mensagens no período; no empate, o
// Instagram (onde a maioria responde post). Sem número no botão: a lista da caixa não filtra por período.
const mainConversations = computed(
  () =>
    ['instagram', 'page']
      .map(source => ({ source, place: data.value?.[source] }))
      .filter(
        ({ place }) =>
          isReady(place) && place.messages?.inbox_id && place.messages.count
      )
      .sort((a, b) => b.place.messages.count - a.place.messages.count)[0]
);

const range = computed(() =>
  periodRange(data.value?.from, data.value?.to, locale.value)
);

// Um botão de destaque por tela: o do topo, quando há conversas; senão a Página primeiro, e o Instagram só quando a
// Página já está pronta.
// Bloqueado é o que pede uma ação da pessoa (liberar ou conectar); Meta fora num lugar só não conta.
const blocked = place =>
  ['needs_permission', 'not_connected'].includes(place?.status);
const bothBlocked = computed(
  () => blocked(page.value) && blocked(instagram.value)
);
const instagramPrimary = computed(() => !blocked(page.value));
// Página e Instagram sem post: o destaque vai para o Instagram, onde a maioria posta.
const bothQuiet = computed(
  () =>
    [page.value, instagram.value].every(isReady) &&
    page.value.reach === 0 &&
    instagram.value.reach === 0
);

// Entrar: sem caixa, a criação da caixa de sempre (inbox_manage). Com caixa sem a permissão, reautoriza a mesma caixa
// pedindo o escopo de Seus posts (integration_manage, a régua do servidor para trocar a credencial da caixa):
// Página → Entrar com Facebook com read_insights, e a tela relê; Instagram → login do Instagram com
// instagram_business_manage_insights, que volta para esta aba (purpose meta_ads_organico, contrato com o #2196).
// A volta do login do Instagram também exige inbox_manage (OauthBinding), mesmo para reautorizar.
const PAGE_EXTRA_SCOPES = ['read_insights'];
const canReauthorize = usePermissionGranted('integration_manage');
const canCreateInbox = usePermissionGranted('inbox_manage');
const canConnect = place => {
  if (place?.status !== 'needs_permission') return canCreateInbox.value;
  if (place === instagram.value)
    return canReauthorize.value && canCreateInbox.value;
  return canReauthorize.value;
};

const { preloadSdk, login } = useFacebookPageConnect();
watch(
  () => page.value?.status === 'needs_permission',
  needsPage => {
    if (needsPage) preloadSdk().catch(() => {});
  }
);

const NEW_INBOX = { page: 'facebook', instagram: 'instagram' };
const reauthorizePage = async inboxId => {
  const token = await login(PAGE_EXTRA_SCOPES);
  if (!token) return;
  await FBChannel.reauthorizeFacebookPage({ omniauthToken: token, inboxId });
  await load();
};
const reauthorizeInstagram = async inboxId => {
  const { data: authorization } = await instagramClient.generateAuthorization({
    inbox_id: inboxId,
    return_to: 'meta_ads',
    purpose: 'meta_ads_organico',
  });
  window.location.href = authorization.url;
};
const connect = async source => {
  const place = data.value?.[source];
  if (place?.status !== 'needs_permission') {
    router.push(
      frontendURL(
        `accounts/${route.params.accountId}/settings/inboxes/new/${NEW_INBOX[source]}`
      )
    );
    return;
  }
  try {
    if (source === 'page') await reauthorizePage(place.inbox_id);
    else await reauthorizeInstagram(place.inbox_id);
  } catch {
    useAlert(t('META_ADS_ORGANIC.CONNECT_ERROR'));
  }
};
</script>

<template>
  <section data-meta-ads-organic class="flex flex-col gap-5 pb-24 sm:pb-0">
    <div
      v-if="loading && !data"
      data-organic-loading
      class="grid items-start gap-5 lg:grid-cols-2"
      aria-busy="true"
      :aria-label="$t('META_ADS_ORGANIC.LOADING')"
    >
      <div
        v-for="index in 2"
        :key="index"
        class="flex animate-pulse flex-col gap-4 rounded-2xl bg-n-solid-1 p-6 ring-1 ring-inset ring-n-weak"
      >
        <div class="h-10 w-1/2 rounded-xl bg-n-alpha-2" />
        <div class="h-20 rounded-xl bg-n-alpha-2" />
        <div class="grid grid-cols-1 gap-3 min-[420px]:grid-cols-2">
          <div
            v-for="tile in 4"
            :key="tile"
            class="h-24 rounded-xl bg-n-alpha-2"
          />
        </div>
      </div>
    </div>

    <div
      v-else-if="failed"
      role="alert"
      data-organic-error
      class="flex flex-col items-start gap-3 rounded-2xl bg-n-solid-1 p-6 ring-1 ring-inset ring-n-weak"
    >
      <p class="m-0 text-base font-semibold text-n-slate-12">
        {{ $t('META_ADS_ORGANIC.ERROR.TEXT') }}
      </p>
      <Button
        icon="i-lucide-refresh-cw"
        :label="$t('META_ADS_ORGANIC.ERROR.RETRY')"
        class="!min-h-11 !rounded-xl"
        @click="load"
      />
    </div>

    <template v-else-if="data">
      <div
        v-if="anyReady"
        role="group"
        :aria-label="$t('META_ADS_ORGANIC.PERIOD_LABEL')"
        class="flex w-fit gap-1 rounded-2xl bg-n-alpha-1 p-1"
      >
        <button
          v-for="key in ROLLING_PERIODS"
          :key="key"
          type="button"
          :data-organic-period="key"
          :aria-pressed="key === period"
          class="min-h-11 whitespace-nowrap rounded-xl border-0 px-3 text-sm font-medium sm:px-4 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
          :class="
            key === period
              ? 'bg-n-solid-1 text-n-slate-12 shadow-sm'
              : 'bg-transparent text-n-slate-11 hover:text-n-slate-12'
          "
          @click="choosePeriod(key)"
        >
          {{ periodLabels[key] }}
        </button>
      </div>

      <div
        data-organic-hero
        class="relative flex flex-col gap-3 overflow-hidden rounded-2xl bg-n-heroi px-5 py-5 text-white ring-1 ring-inset ring-white/10 transition-opacity dark:bg-n-heroi-escuro sm:px-7 sm:py-6"
        :class="{ 'opacity-60': loading }"
      >
        <span
          aria-hidden="true"
          class="pointer-events-none absolute -end-16 -top-24 size-72 rounded-full border-[3rem] border-n-teal-9 opacity-15"
        />
        <p
          v-if="anyReady && range"
          data-organic-range
          class="relative m-0 text-pretty text-sm font-medium text-white/70"
        >
          {{ $t('META_ADS_ORGANIC.RANGE', { range }) }}
        </p>
        <h3
          data-organic-headline
          class="relative m-0 max-w-3xl text-balance text-2xl font-bold leading-tight tracking-tight text-white tabular-nums sm:text-3xl"
        >
          {{ headline }}
        </h3>
        <p
          v-if="bestPost"
          data-organic-best-post
          class="relative m-0 max-w-3xl text-base text-white/85"
        >
          {{ $t('META_ADS_ORGANIC.BEST_POST', bestPost) }}
        </p>
        <button
          v-if="mainConversations"
          type="button"
          data-organic-main-conversations
          class="relative inline-flex min-h-11 w-fit items-center justify-center gap-1.5 whitespace-nowrap rounded-lg border-0 bg-white px-4 text-sm font-520 text-n-heroi hover:bg-n-blue-2 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-white"
          @click="openConversations(mainConversations.place.messages.inbox_id)"
        >
          <span class="i-lucide-message-circle size-4" aria-hidden="true" />
          {{ seeConversationsLabels[mainConversations.source] }}
        </button>
      </div>

      <div
        class="grid items-start gap-5 lg:grid-cols-2"
        :class="{ 'pointer-events-none opacity-60': loading }"
        :aria-busy="loading"
      >
        <OrganicSourceCard
          source="page"
          :data="page"
          :days="days"
          :read-only="readOnly || !canConnect(page)"
          :primary="!bothQuiet && !mainConversations"
          :step="bothBlocked ? 1 : null"
          :main="mainConversations?.source === 'page'"
          @connect="connect"
          @conversations="openConversations"
          @retry="load"
        />
        <OrganicSourceCard
          source="instagram"
          :data="instagram"
          :days="days"
          :read-only="readOnly || !canConnect(instagram)"
          :primary="instagramPrimary && !mainConversations"
          :step="bothBlocked ? 2 : null"
          :main="mainConversations?.source === 'instagram'"
          :class="{ 'order-first lg:order-none': bothQuiet }"
          @connect="connect"
          @conversations="openConversations"
          @retry="load"
        />
      </div>
    </template>
  </section>
</template>
