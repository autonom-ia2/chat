<script setup>
import {
  computed,
  nextTick,
  onBeforeUnmount,
  onMounted,
  ref,
  watch,
} from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { frontendURL } from 'dashboard/helper/URLHelper';
import Button from 'dashboard/components-next/button/Button.vue';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import { todayIso, todayOfAccount } from '../dinheiroDoAnuncio';
import { useDinheiroDoRascunho } from '../useDinheiroDoRascunho';
import {
  botaoDoAnuncio,
  destinosDaConta,
  lugaresDoDestino,
  siteValido,
} from '../anuncioNovo';
import {
  criarAnuncio,
  esquecerTentativas,
  lerOpcoesDeCriacao,
  pedidoDoAnuncio,
} from '../criacaoNaMeta';
import { useMetaAdsFacebookLogin } from '../useMetaAdsFacebookLogin';
import { useImpulsionarPost } from '../useImpulsionarPost';
import MetaAdsCreateAudience from './MetaAdsCreateAudience.vue';
import MetaAdsCreateBudget from './MetaAdsCreateBudget.vue';
import MetaAdsCreateContent from './MetaAdsCreateContent.vue';
import MetaAdsCreateDone from './MetaAdsCreateDone.vue';
import MetaAdsCreateKind from './MetaAdsCreateKind.vue';
import MetaAdsCreatePost from './MetaAdsCreatePost.vue';
import MetaAdsCreateReview from './MetaAdsCreateReview.vue';

// Anúncios da Meta (#2198), o Gerenciador simples, sem sair do painel. Anúncio novo, uma pergunta por tela: foto,
// vídeo ou carrossel e o texto (com "Quem tocar vai para: WhatsApp · Trocar" no topo) → quem vê → quanto investir →
// conferir (com "Onde aparece: Automático · Trocar"). A escolha "O que fazer" só aparece quando o servidor oferece
// mais de um tipo (`kinds` das opções); com um só, a tela entra direto nele. A Página e o número só viram passo
// quando há mais de um. O resto começa pronto (R$ 20,00 por dia, hoje, sem data para terminar). O anúncio nasce
// PAUSADO (campanha e grupo ativos, gasto zero); a tela final já traz o "Ativar anúncio", que mostra quanto vai
// gastar antes de o dinheiro começar a sair. Impulsionar post (#2339): o post (abas Instagram e Facebook) → quem vê →
// quanto investir → conferir, também pausado.
const props = defineProps({
  // 'ad' (anúncio novo) ou 'post' (impulsionar): o botão que abriu já escolhe.
  kind: { type: String, default: null },
});

const emit = defineEmits(['back']);

const { t, locale } = useI18n();
const route = useRoute();
const router = useRouter();
const KEY = 'CRM_KANBAN.META_ADS_HUB.CRIAR';
const SUGGESTED_DAILY = 20;
// Recusas que a tela sabe explicar; outra vira a frase geral.
const CREATE_ERRORS = [
  'invalid_params',
  'invalid_destination',
  'invalid_placement',
  'invalid_amount',
  'invalid_dates',
  'invalid_site',
  'invalid_whatsapp_number',
  'invalid_page',
  'invalid_media',
  'invalid_audience',
  'video_processing',
  'cannot_create',
  'meta_unavailable',
  'meta_refused',
  'currency_not_supported',
  'unconfirmed',
  'invalid_post',
  'post_not_eligible',
];
// Os limites e o valor são em reais: conta de anúncios em outra moeda não cria por aqui.
const ACCOUNT_CURRENCY = 'BRL';
const HTTP_CONFLICT = 409;

const options = ref(null);
const loading = ref(true);
const loadFailed = ref(false);
// Sem conexão ativa com conta de anúncios (404 not_connected, #2338: sem conexão, caída ou sem a conta escolhida): não é
// a Meta fora do ar, é um passo que falta. A Conexão abre no passo certo.
const noAdAccount = ref(false);
const heading = ref(null);
const created = ref(null);
const saving = ref(false);
const createError = ref('');

// O valor no campo como a pessoa escreveria: "20,00" em português, "20.00" em inglês.
const editable = value =>
  new Intl.NumberFormat(locale.value.startsWith('pt') ? 'pt-BR' : 'en-US', {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
    useGrouping: false,
  }).format(value);

const draft = ref({
  kind: props.kind,
  page_id: null,
  whatsapp_number: null,
  // Para onde vai quem toca no anúncio novo: o primeiro destino confirmado para a conta (WhatsApp, quando veio).
  destination: null,
  site_url: '',
  site_action: 'LEARN_MORE',
  media: null,
  // Carrossel: as mídias depois da primeira.
  more_media: [],
  // A foto (ou um cartão do carrossel) ainda subindo para a Meta.
  uploading_media: false,
  uploading_cards: false,
  offer: '',
  text: '',
  headline: '',
  // A pessoa mexeu no texto ou no título: mudar o que vende não reescreve mais.
  text_edited: false,
  headline_edited: false,
  ready_message: '',
  placement: 'AUTO',
  region: 'BR',
  states: [],
  age_min: 18,
  age_max: 65,
  special_category: null,
  daily_amount: '',
  start_date: todayIso(),
  end_date: '',
  name: '',
  // Impulsionar: de onde é o post e qual.
  post_source: 'facebook',
  post_id: null,
});

const step = ref(0);

const pages = computed(() => options.value?.pages || []);
const numbers = computed(() => options.value?.whatsapp_numbers || []);
const kinds = computed(() => options.value?.kinds || []);
// O tipo já decidido: pelo botão que abriu, ou porque o servidor só oferece um.
const fixedKind = computed(
  () => props.kind || (kinds.value.length === 1 ? kinds.value[0] : null)
);

// Página e número só perguntam quando há escolha a fazer.
const needsWhere = computed(
  () => pages.value.length > 1 || numbers.value.length > 1
);

const isPost = computed(() => draft.value.kind === 'post');
const STEPS = computed(() => [
  'KIND',
  ...(needsWhere.value ? ['WHERE'] : []),
  isPost.value ? 'POST' : 'CONTENT',
  'AUDIENCE',
  'BUDGET',
  'REVIEW',
]);
const current = computed(() => STEPS.value[step.value]);
const total = computed(() => STEPS.value.length - 1);

const impulsionar = useImpulsionarPost({ draft, numbers });
const { postEscolhido, botaoDoPost } = impulsionar;

// O que impede criar: entrar de novo, sem Página, sem número (anúncio para o WhatsApp) ou sem post para impulsionar.
const blocker = computed(() => {
  if (noAdAccount.value) return 'NO_AD_ACCOUNT';
  if (!options.value) return null;
  if (options.value.needs_login) return 'LOGIN';
  if (options.value.currency !== ACCOUNT_CURRENCY) return 'CURRENCY';
  if (!draft.value.kind) return null;
  if (!pages.value.length) return 'NO_PAGE';
  if (isPost.value) return impulsionar.semPosts.value ? 'NO_POST' : null;
  if (draft.value.destination === 'WHATSAPP' && !numbers.value.length) {
    return 'NO_NUMBER';
  }
  return null;
});

const focusHeading = () => nextTick(() => heading.value?.focus());
watch(step, () => {
  createError.value = '';
  focusHeading();
});

const { amountError, perDayLine, totalLine, dayLimitsLine } =
  useDinheiroDoRascunho({ draft, options, locale, t });

const chosenNumber = computed(() =>
  numbers.value.find(number => number.id === draft.value.whatsapp_number)
);
const chosenPage = computed(() =>
  pages.value.find(page => page.id === draft.value.page_id)
);
// O Instagram da Página escolhida (cada Página tem o seu, ou nenhum).
const instagram = computed(() => chosenPage.value?.instagram || null);

// O botão do anúncio: o do destino; no post, o do post.
const action = computed(() =>
  isPost.value ? botaoDoPost.value : botaoDoAnuncio(draft.value)
);
// Só o que a chamada real já confirmou para a conta: os destinos e, para o destino do anúncio, os lugares. Lugar
// escolhido que deixa de valer (trocou o destino) volta para Automático.
const destinations = computed(() => destinosDaConta(options.value));
// Post do Instagram vai em Automático; o da Página, só no Facebook (o servidor manda assim).
const placements = computed(() => {
  if (isPost.value) {
    return draft.value.post_source === 'facebook' ? ['FACEBOOK'] : ['AUTO'];
  }
  return lugaresDoDestino(options.value, draft.value.destination);
});
watch(placements, list => {
  // O post tem lugar fixo (o servidor decide); só o anúncio novo volta para Automático.
  if (isPost.value) return;
  if (!list.includes(draft.value.placement)) {
    draft.value = { ...draft.value, placement: 'AUTO' };
  }
});

const adCards = computed(() =>
  draft.value.media ? [draft.value.media, ...draft.value.more_media] : []
);

const pageOptions = computed(() =>
  pages.value.map(page => ({ value: page.id, label: page.name }))
);
const numberOptions = computed(() =>
  numbers.value.map(number => ({
    value: number.id,
    label: `${number.name} · ${number.phone}`,
  }))
);

// O que falta para o "Continuar", na ordem dos campos da tela; '' quando nada falta.
const contentMissing = computed(() => {
  const { destination, site_url: url, offer, media, text } = draft.value;
  if (destination === 'WEBSITE' && !siteValido(url)) return 'NEED_SITE';
  if (!offer.trim()) return 'NEED_OFFER';
  if (draft.value.uploading_media || draft.value.uploading_cards) {
    return 'UPLOADING';
  }
  if (!media) return 'NEED_MEDIA';
  if (!text.trim()) return 'NEED_TEXT';
  return '';
});
const STEP_READY = {
  KIND: () => Boolean(draft.value.kind),
  // Com um número só (ou nenhum), ele não é pergunta: já vem escolhido ou o destino não é o WhatsApp.
  WHERE: () =>
    Boolean(
      draft.value.page_id &&
        (numbers.value.length <= 1 || draft.value.whatsapp_number)
    ),
  CONTENT: () => !contentMissing.value,
  // Enquanto lê (ou relê para outra Página), o post marcado ainda pode ser o da leitura anterior.
  POST: () =>
    !impulsionar.lendo.value &&
    !impulsionar.falhou.value &&
    Boolean(postEscolhido.value?.eligible),
  AUDIENCE: () =>
    draft.value.special_category !== null &&
    (draft.value.region === 'BR' || draft.value.states.length > 0) &&
    draft.value.age_min <= draft.value.age_max,
  BUDGET: () => !amountError.value,
  REVIEW: () => Boolean(draft.value.name.trim()),
};
const ready = computed(() => STEP_READY[current.value]());

const blockReason = computed(() => {
  if (current.value === 'CONTENT' && contentMissing.value) {
    return t(`${KEY}.CONTENT.${contentMissing.value}`);
  }
  const lendoPosts = impulsionar.lendo.value || impulsionar.falhou.value;
  if (current.value === 'POST' && !ready.value && !lendoPosts) {
    return t(`${KEY}.POST.NEED_POST`);
  }
  return '';
});

// Idade mínima maior que a máxima: o "Continuar" desliga e a tela diz por quê.
const ageError = computed(
  () =>
    current.value === 'AUDIENCE' && draft.value.age_min > draft.value.age_max
);
// No celular a frase nasce perto do rodapé, atrás da barra fixa: a tela rola até ela (scroll-mb-28 desconta a barra).
const ageErrorEl = ref(null);
watch(ageError, async shown => {
  if (!shown) return;
  await nextTick();
  ageErrorEl.value?.scrollIntoView({ block: 'nearest' });
});

const defaultName = () => {
  const date = new Date().toLocaleDateString(
    locale.value.startsWith('pt') ? 'pt-BR' : 'en-US',
    { day: 'numeric', month: 'short' }
  );
  if (isPost.value) return t(`${KEY}.REVIEW.DEFAULT_NAME_POST`, { date });
  return t(`${KEY}.REVIEW.DEFAULT_NAME_AD`, {
    where: t(`${KEY}.DESTINATION.SHORT.${draft.value.destination}`),
    date,
  });
};

const next = () => {
  if (!ready.value) return;
  if (STEPS.value[step.value + 1] === 'REVIEW' && !draft.value.name) {
    draft.value = { ...draft.value, name: defaultName() };
  }
  step.value += 1;
};

// Não confirmado na Meta: a pessoa confere no Gerenciador de Anúncios e só ela libera criar de novo. Recriar manda o
// pedido guardado da tentativa (mesma chave), e a edição fica travada enquanto isso, para o anúncio novo ser o mesmo
// que a pessoa conferiu.
const unconfirmed = ref(false);
const pendingPedido = ref(null);

// Voltar sai para o painel no primeiro passo (o da escolha, ou o seguinte quando o tipo já veio decidido).
const leavesToPanel = computed(
  () => step.value === 0 || (fixedKind.value && step.value === 1)
);
const back = () => {
  // Tentativa não confirmada: o rascunho fica como foi mandado até a pessoa resolver.
  if (unconfirmed.value) return;
  // No bloqueio depois de escolher o que fazer: volta à escolha.
  if (blocker.value && draft.value.kind && !fixedKind.value) {
    draft.value = { ...draft.value, kind: null };
    return;
  }
  if (leavesToPanel.value) {
    emit('back');
    return;
  }
  step.value -= 1;
};

const chooseKind = kind => {
  draft.value = { ...draft.value, kind };
  if (!blocker.value) step.value = 1;
};

// "Nada foi criado" só quando o servidor garante (`nothing_created`). Sem garantia, pede para conferir na Meta.
const createErrorText = error => {
  const response = error?.response;
  if (!response) return t(`${KEY}.ERRORS.NETWORK`);
  if (response.status === HTTP_CONFLICT) return t(`${KEY}.ERRORS.IN_PROGRESS`);
  const { error: code, nothing_created: nothingCreated } = response.data || {};
  const reason = CREATE_ERRORS.includes(code)
    ? t(`${KEY}.ERRORS.${code.toUpperCase()}`)
    : t(`${KEY}.ERRORS.UNKNOWN`);
  // Não confirmado: a frase já diz para conferir no Gerenciador de Anúncios.
  if (code === 'unconfirmed') return reason;
  if (nothingCreated === true) {
    return `${reason} ${t(`${KEY}.ERRORS.NOTHING_CREATED`)}`;
  }
  if (nothingCreated === false) {
    return `${reason} ${t(`${KEY}.ERRORS.CHECK_META`)}`;
  }
  return reason;
};

const create = async ({ recriar = false } = {}) => {
  if (!ready.value || saving.value) return;
  saving.value = true;
  createError.value = '';
  const pedido = recriar ? pendingPedido.value : pedidoDoAnuncio(draft.value);
  try {
    created.value = await criarAnuncio(pedido, { recriar });
    unconfirmed.value = false;
    pendingPedido.value = null;
    focusHeading();
  } catch (error) {
    createError.value = createErrorText(error);
    unconfirmed.value = error?.response?.data?.error === 'unconfirmed';
    pendingPedido.value = unconfirmed.value ? pedido : null;
  } finally {
    saving.value = false;
  }
};

const recreate = () => create({ recriar: true });

// Saiu do fluxo: a chave da tentativa sai da memória. Voltar com o mesmo pedido não cria outra campanha: o servidor
// acha a tentativa pelo pedido e devolve a chave dela.
onBeforeUnmount(esquecerTentativas);

const submitLabel = computed(() => {
  if (current.value !== 'REVIEW') return t(`${KEY}.NEXT`);
  return isPost.value ? t(`${KEY}.CREATE_BOOST`) : t(`${KEY}.CREATE`);
});

// Os posts são lidos ao chegar no passo do post (e de novo se a Página mudou).
watch(current, value => {
  if (value === 'POST') impulsionar.lerSePreciso();
});

const submit = () => {
  if (unconfirmed.value) return;
  if (current.value === 'REVIEW') create();
  else next();
};

// Com uma opção só, ela já vem escolhida.
const prefill = data => {
  const [destination = null] = destinosDaConta(data);
  const kind = draft.value.kind || fixedKind.value;
  draft.value = {
    ...draft.value,
    // Sem destino confirmado, o "Anúncio novo" fica apagado na escolha, com o motivo.
    kind: kind === 'ad' && !destination ? null : kind,
    destination,
    // O dia de hoje no fuso da conta de anúncios, como o servidor confere.
    start_date: todayOfAccount(data.today),
    page_id: data.pages.length === 1 ? data.pages[0].id : null,
    whatsapp_number:
      data.whatsapp_numbers.length === 1 ? data.whatsapp_numbers[0].id : null,
    ready_message: t(`${KEY}.CONTENT.READY_MESSAGE_DEFAULT`),
    daily_amount: editable(SUGGESTED_DAILY),
  };
};

const load = async () => {
  loading.value = true;
  loadFailed.value = false;
  noAdAccount.value = false;
  try {
    const data = await lerOpcoesDeCriacao();
    options.value = data;
    prefill(data);
    if (draft.value.kind && !blocker.value) step.value = 1;
  } catch (error) {
    if (error?.response?.data?.error === 'not_connected') {
      noAdAccount.value = true;
    } else {
      loadFailed.value = true;
    }
  } finally {
    loading.value = false;
    focusHeading();
  }
};

onMounted(load);

// Saídas dos bloqueios: entrar com o Facebook ali mesmo (a configuração vem nas opções), Conexão (Página), caixas
// de entrada (número).
const goToConnection = () => router.replace({ query: { aba: 'conexao' } });
// Escolhida a conta na Conexão, a pessoa volta para criar o anúncio (`?volta=criar`).
const chooseAdAccount = () =>
  router.replace({ query: { aba: 'conexao', volta: 'criar' } });
const { isConnecting, connect } = useMetaAdsFacebookLogin();
const loginNotice = ref('');
const signIn = async () => {
  const config = options.value?.facebook_login;
  if (!config?.configuration_id) {
    goToConnection();
    return;
  }
  loginNotice.value = '';
  try {
    const data = await connect(config);
    if (data) await load();
    else loginNotice.value = t(`${KEY}.BLOCKERS.LOGIN.POPUP`);
  } catch {
    loginNotice.value = t(`${KEY}.BLOCKERS.LOGIN.ERROR`);
  }
};
const goToInboxes = () =>
  router.push(
    frontendURL(`accounts/${route.params.accountId}/settings/inboxes/new`)
  );
// Sem número de WhatsApp: dá para anunciar com outro destino confirmado (o primeiro da lista), em vez de parar.
const otherDestination = computed(() =>
  destinations.value.find(option => option !== 'WHATSAPP')
);
const adWithoutWhatsapp = () => {
  draft.value = { ...draft.value, destination: otherDestination.value };
  step.value = 1;
};

// Sem a configuração do login no servidor, o botão diz a verdade: leva à Conexão.
const blockerAction = computed(() =>
  blocker.value === 'LOGIN' && !options.value?.facebook_login?.configuration_id
    ? t(`${KEY}.BLOCKERS.LOGIN.ACTION_CONNECTION`)
    : t(`${KEY}.BLOCKERS.${blocker.value}.ACTION`)
);

// Sem post para impulsionar: segue com o anúncio novo, quando a conta pode criar um (tem destino).
const canSwitchToAd = computed(
  () => kinds.value.includes('ad') && destinations.value.length > 0
);
const switchToAd = () => chooseKind('ad');

const BLOCKERS = {
  LOGIN: { icon: 'i-lucide-log-in', action: signIn },
  NO_AD_ACCOUNT: { icon: 'i-lucide-briefcase', action: chooseAdAccount },
  NO_PAGE: { icon: 'i-lucide-flag', action: goToConnection },
  CURRENCY: { icon: 'i-lucide-banknote', action: goToConnection },
  NO_POST: { icon: 'i-lucide-image-off', action: switchToAd },
  NO_NUMBER: {
    icon: 'i-ri-whatsapp-line',
    action: goToInboxes,
    other: adWithoutWhatsapp,
  },
};
</script>

<template>
  <section
    data-meta-ads-create
    class="flex min-w-0 flex-col gap-5 pb-28 md:pb-0"
  >
    <button
      v-if="!created"
      type="button"
      data-create-back
      :disabled="unconfirmed"
      class="inline-flex min-h-11 items-center gap-1.5 self-start rounded-xl border-0 bg-transparent p-0 text-sm font-medium text-n-blue-11 hover:underline focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
      @click="back"
    >
      <span class="i-lucide-arrow-left size-4" aria-hidden="true" />
      {{
        leavesToPanel && !(blocker && draft.kind && !fixedKind)
          ? $t(`${KEY}.BACK_TO_PANEL`)
          : $t(`${KEY}.BACK`)
      }}
    </button>

    <div v-if="loading" class="flex justify-center p-12"><Spinner /></div>

    <!-- Falha ao falar com a Meta: nada foi criado, e dá para tentar de novo. -->
    <div
      v-else-if="loadFailed"
      data-create-failed
      class="flex flex-col items-start gap-4 rounded-2xl bg-n-solid-1 p-6 ring-1 ring-inset ring-n-weak sm:p-8"
    >
      <span
        class="i-lucide-cloud-off size-8 text-n-ruby-11"
        aria-hidden="true"
      />
      <h2
        ref="heading"
        tabindex="-1"
        class="m-0 text-lg font-semibold text-n-slate-12 focus:outline-none"
      >
        {{ $t(`${KEY}.FAILED.TITLE`) }}
      </h2>
      <Button :label="$t(`${KEY}.FAILED.RETRY`)" @click="load" />
    </div>

    <!-- Criado: pausado, com o "Ativar anúncio" à mão. -->
    <MetaAdsCreateDone
      v-else-if="created"
      :created="created"
      :budget="created.budget"
      @back="emit('back')"
    />

    <!-- Bloqueio antes de começar: uma frase e a saída. -->
    <div
      v-else-if="blocker"
      :data-create-blocker="blocker"
      class="flex flex-col items-start gap-4 rounded-2xl bg-n-solid-1 p-6 ring-1 ring-inset ring-n-weak sm:p-8"
    >
      <span
        :class="BLOCKERS[blocker].icon"
        class="size-8 text-n-brand"
        aria-hidden="true"
      />
      <h2
        ref="heading"
        tabindex="-1"
        class="m-0 text-lg font-semibold text-n-slate-12 focus:outline-none"
      >
        {{ $t(`${KEY}.BLOCKERS.${blocker}.TITLE`) }}
      </h2>
      <Button
        v-if="blocker !== 'NO_POST' || canSwitchToAd"
        :data-create-blocker-action="blocker"
        :label="blockerAction"
        :is-loading="blocker === 'LOGIN' && isConnecting"
        @click="BLOCKERS[blocker].action"
      />
      <button
        v-if="BLOCKERS[blocker].other && otherDestination"
        type="button"
        :data-create-blocker-other="blocker"
        class="inline-flex min-h-11 items-center rounded-xl border-0 bg-transparent p-0 text-sm font-medium text-n-blue-11 hover:underline focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
        @click="BLOCKERS[blocker].other"
      >
        {{ $t(`${KEY}.BLOCKERS.${blocker}.OTHER`) }}
      </button>
      <p
        v-if="blocker === 'LOGIN' && loginNotice"
        data-create-login-notice
        role="status"
        class="m-0 text-sm text-n-amber-11"
      >
        {{ loginNotice }}
      </p>
    </div>

    <form
      v-else
      data-create-form
      :data-create-step="current"
      class="flex min-w-0 flex-col gap-6 rounded-2xl bg-n-solid-1 p-5 ring-1 ring-inset ring-n-weak sm:p-8"
      @submit.prevent="submit"
    >
      <div class="flex flex-col gap-2">
        <div v-if="step > 0" data-create-progress class="flex flex-col gap-1.5">
          <span class="text-xs font-medium text-n-slate-10">
            {{ $t(`${KEY}.PROGRESS`, { step, total }) }}
          </span>
          <span
            role="progressbar"
            :aria-valuenow="step"
            aria-valuemin="0"
            :aria-valuemax="total"
            :aria-label="$t(`${KEY}.PROGRESS`, { step, total })"
            class="block h-1.5 w-full max-w-xs overflow-hidden rounded-full bg-n-alpha-2"
          >
            <span
              class="block h-full rounded-full bg-n-brand transition-all"
              :style="{ width: `${(step / total) * 100}%` }"
            />
          </span>
        </div>
        <h2
          ref="heading"
          tabindex="-1"
          class="m-0 text-xl font-semibold text-n-slate-12 focus:outline-none"
        >
          {{ $t(`${KEY}.${current}.TITLE`) }}
        </h2>
        <p class="m-0 max-w-prose text-sm leading-6 text-n-slate-11">
          {{ $t(`${KEY}.${current}.HINT`) }}
        </p>
      </div>

      <!-- Não confirmado: nada do rascunho muda até a pessoa resolver (o recriar manda o pedido como foi). -->
      <fieldset
        :disabled="unconfirmed"
        data-create-fields
        class="contents m-0 min-w-0 border-0 p-0"
      >
        <MetaAdsCreateKind
          v-if="current === 'KIND'"
          :model-value="draft.kind"
          :kinds="kinds"
          :unavailable="destinations.length ? {} : { ad: 'NO_DESTINATION' }"
          @choose="chooseKind"
        />

        <div
          v-else-if="current === 'WHERE'"
          class="flex min-w-0 max-w-xl flex-col gap-5"
        >
          <div v-if="pages.length > 1" class="flex flex-col gap-2">
            <span class="text-sm font-medium text-n-slate-12">
              {{ $t(`${KEY}.WHERE.PAGE`) }}
            </span>
            <ChoiceSelect
              :model-value="draft.page_id"
              data-create-page
              :options="pageOptions"
              :aria-label="$t(`${KEY}.WHERE.PAGE`)"
              :placeholder="$t(`${KEY}.WHERE.CHOOSE`)"
              class="w-full"
              @update:model-value="draft = { ...draft, page_id: $event }"
            />
          </div>
          <div v-if="numbers.length > 1" class="flex flex-col gap-2">
            <span class="text-sm font-medium text-n-slate-12">
              {{ $t(`${KEY}.WHERE.NUMBER`) }}
            </span>
            <ChoiceSelect
              :model-value="draft.whatsapp_number"
              data-create-number
              :options="numberOptions"
              :aria-label="$t(`${KEY}.WHERE.NUMBER`)"
              :placeholder="$t(`${KEY}.WHERE.CHOOSE`)"
              class="w-full"
              @update:model-value="
                draft = { ...draft, whatsapp_number: $event }
              "
            />
          </div>
        </div>

        <MetaAdsCreateContent
          v-else-if="current === 'CONTENT'"
          v-model="draft"
          :library="options.images"
          :page-name="chosenPage?.name"
          :phone="chosenNumber?.phone"
          :has-number="numbers.length > 0"
          :instagram="instagram"
          :destinations="destinations"
        />

        <MetaAdsCreatePost
          v-else-if="current === 'POST'"
          v-model="draft"
          :posts="impulsionar.posts.value"
          :instagram-posts="impulsionar.postsDoInstagram.value"
          :has-instagram="Boolean(instagram)"
          :has-number="numbers.length > 0"
          :loading="impulsionar.lendo.value"
          :failed="impulsionar.falhou.value"
          @retry="impulsionar.lerPosts"
        />

        <MetaAdsCreateAudience
          v-else-if="current === 'AUDIENCE'"
          v-model="draft"
        />

        <MetaAdsCreateBudget
          v-else-if="current === 'BUDGET'"
          v-model="draft"
          :limits="options"
          :amount-error="amountError"
          :total-line="totalLine"
          :day-limits-line="dayLimitsLine"
          :suggestion="SUGGESTED_DAILY"
        />

        <MetaAdsCreateReview
          v-else-if="current === 'REVIEW'"
          v-model="draft"
          :page-name="chosenPage?.name"
          :phone="chosenNumber?.phone"
          :username="instagram?.username"
          :media="isPost ? postEscolhido?.media : draft.media"
          :cards="isPost ? [] : adCards"
          :post-text="postEscolhido?.text"
          :action="action"
          :per-day-line="perDayLine"
          :total-line="totalLine"
          :day-limits-line="dayLimitsLine"
          :placements="placements"
        />
      </fieldset>

      <p
        v-if="ageError"
        ref="ageErrorEl"
        data-create-age-error
        role="status"
        class="m-0 scroll-mb-28 text-sm text-n-ruby-11"
      >
        {{ $t(`${KEY}.AUDIENCE.AGE_ERROR`) }}
      </p>
      <!-- Recusa ao criar: a frase fica na tela até a pessoa tentar de novo. -->
      <p
        v-if="createError"
        data-create-error
        role="alert"
        class="m-0 flex gap-2 rounded-xl bg-n-ruby-2 p-3 text-sm text-n-ruby-12"
      >
        <span
          class="i-lucide-circle-alert mt-0.5 size-4 shrink-0"
          aria-hidden="true"
        />
        {{ createError }}
      </p>
      <Button
        v-if="unconfirmed"
        data-create-recreate
        outline
        :label="$t(`${KEY}.RECREATE`)"
        :is-loading="saving"
        @click="recreate"
      />
      <!-- No celular o "Continuar" fica preso no rodapé, sempre à mão. O botão do menu (☰) fica no canto da barra,
           ao lado do "Continuar": a margem da esquerda é dele. -->
      <div
        v-if="current !== 'KIND'"
        data-create-actions
        class="fixed inset-x-0 bottom-0 z-30 flex gap-3 border-t border-n-weak bg-n-solid-1 pb-[calc(1rem+env(safe-area-inset-bottom))] pl-20 pr-4 pt-3 md:static md:z-auto md:border-0 md:bg-transparent md:p-0"
      >
        <div
          class="flex min-w-0 flex-1 flex-col gap-2 md:flex-row md:items-center md:gap-4"
        >
          <Button
            class="w-full md:w-auto"
            type="submit"
            :data-create-next="current"
            :label="submitLabel"
            :disabled="!ready || unconfirmed"
            :is-loading="saving"
          />
          <p
            v-if="blockReason"
            data-create-block-reason
            role="status"
            class="order-first m-0 text-xs text-n-slate-11 md:order-none md:text-sm"
          >
            {{ blockReason }}
          </p>
        </div>
      </div>
    </form>
  </section>
</template>
