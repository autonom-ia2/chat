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
import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import CrmMetaAdsConnectionAPI from 'dashboard/api/crmMetaAdsConnection';
import { amount, errorMessageKey, relativeTime } from '../metaAdsHelpers';
import { useMetaAdsFacebookLogin } from '../useMetaAdsFacebookLogin';
import { SEM_LOGIN } from './anunciosSemLogin';
import MetaTelaGuia from './MetaTelaGuia.vue';
import MetaAdsDestinationsStep from '../components/MetaAdsDestinationsStep.vue';
import MetaAdsSiteLinkDialog from '../components/MetaAdsSiteLinkDialog.vue';

// Conectar a conta de anúncios a partir do painel sem login (#2054), sem ninguém da plataforma no portfólio do
// cliente. Uma ação por tela:
//   começo → Entrar com o Facebook → (a conta aparece sozinha) Conectar → para onde o anúncio leva → pronto
// O destino (#2338) é o mesmo passo da aba Conexão (MetaAdsDestinationsStep): WhatsApp, site ou os dois, e a página
// do site ligada ali mesmo.
// Outros jeitos, para quem precisa: "Outra pessoa cuida dos meus anúncios" (mensagem pronta para mandar, com o
// compartilhamento como parceiro) e o próprio compartilhamento passo a passo (copiar → abrir a Meta → marcar).
// "Conferir" só lê (ad_accounts); quem grava a conta é "Conectar esta conta" (selection), com o toque da pessoa.
// O código do site (Pixel) (#2343): com um só, vai junto sem perguntar; com mais de um, uma tela pergunta qual (a
// Meta não diz qual a pessoa marcou na janela do Facebook). Sem nenhum, a conta conecta sem código do site.
// Ainda não chegou: a tela confere de novo sozinha algumas vezes antes de pedir o toque.
// `resume` (connection_state do servidor): 'choosing' volta direto para a escolha da conta; 'broken' começa do
// início com o aviso de que a conexão caiu.
const props = defineProps({
  // payload de GET meta_ads_connection: facebook_login, partner, client_portfolio_id
  connection: { type: Object, required: true },
  resume: { type: Object, default: null },
});
const emit = defineEmits(['back', 'connected']);

const C = `${SEM_LOGIN}.CONNECT`;
const META_PARTNERS_URL =
  'https://business.facebook.com/latest/settings/partners';
const RECHECK_SECONDS = 20;
const RECHECK_TIMES = 3;
const FACEBOOK_STEPS = ['ENTER', 'CHOOSE', 'WHERE', 'SEE'];
const PARTNER_STEPS = ['copy', 'meta', 'mark'];
// Opção "Não tenho site" no "Alterar" do código do site.
const NO_SITE = 'none';

const { t, locale } = useI18n();
const {
  isConnecting,
  preload,
  connect: facebookConnect,
} = useMetaAdsFacebookLogin();
const facebook = computed(() => props.connection.facebook_login || {});
const hasFacebook = computed(() => Boolean(facebook.value.available));

const screen = ref(hasFacebook.value ? 'start' : 'copy');
const mode = ref(hasFacebook.value ? 'facebook_login' : 'partner');
const viaSomeone = ref(false);
const accounts = ref([]);
const errorCode = ref(null);
const loginNotice = ref(null);
const chosen = ref(null);
const copied = ref(false);
const rechecks = ref(0);
const autoChecking = ref(false);
const pixels = ref([]);
const pixel = ref(null);
const pixelFailed = ref(false);
const pickingPixel = ref(false);
const pixelChoice = ref('');
const savingPixel = ref(false);
const pixelError = ref(null);
const root = ref(null);
let recheckTimer = null;

const partnerName = computed(
  () => props.connection.partner?.business_name || 'Autonom.ia'
);
const partnerId = computed(() => props.connection.partner?.business_id || '');
const partnersUrl = computed(() => {
  const portfolio = props.connection.client_portfolio_id;
  return portfolio
    ? `${META_PARTNERS_URL}?business_id=${encodeURIComponent(portfolio)}`
    : META_PARTNERS_URL;
});
const partnerStep = computed(() => PARTNER_STEPS.indexOf(screen.value) + 1);
// Depois de entrar com o Facebook, a faixa "Entrar → Confirmar → Destino → Ver" mostra onde a pessoa está.
const FACEBOOK_SCREENS = {
  checking: 2,
  found: 2,
  choose: 2,
  pixel: 2,
  connecting: 2,
  notyet: 2,
  destino: 3,
  done: 4,
};
const facebookStep = computed(() =>
  mode.value === 'facebook_login' ? FACEBOOK_SCREENS[screen.value] || 0 : 0
);
const broken = computed(() => props.resume?.state === 'broken');
// Quem conecta a partir do WhatsApp mede o WhatsApp: conta sem destino nenhum (o servidor manda os dois falsos)
// ganha o WhatsApp marcado; conta que já escolheu segue com a escolha.
const WHATSAPP_ONLY = { whatsapp: true, site: false };
const NONE = { whatsapp: false, site: false };
// Gravar o WhatsApp antes falhou: o passo 3 mostra a conta como ela está (nada marcado) e pede a escolha.
const preWriteFailed = ref(false);
const chosenDestinations = computed(() => {
  const current = props.connection.destinations;
  return current?.whatsapp || current?.site ? current : null;
});
const destinations = computed(() => {
  if (chosenDestinations.value) return chosenDestinations.value;
  return preWriteFailed.value ? NONE : WHATSAPP_ONLY;
});
// Gravar o destino falhou no passo 3: "Escolher depois" deixa seguir, e o pronto diz onde escolher.
const destinationFailed = ref(false);
const destinationLater = ref(false);
// O que o passo 3 gravou: com o site marcado e nenhuma página ligada, o pronto pede para ligar a página.
const savedDestination = ref(null);
const pageMissing = computed(
  () =>
    Boolean(savedDestination.value?.destinations?.site) &&
    savedDestination.value.site_pages_count === 0
);
const linkDialog = ref(null);
// Depois de conectar, voltar sairia do passo a passo com a conta já ligada: o "Voltar" some.
const canGoBack = computed(
  () => screen.value !== 'destino' && screen.value !== 'done'
);
const message = computed(() =>
  t(`${C}.SEND.MESSAGE`, {
    partner: partnerName.value,
    id: partnerId.value,
    link: partnersUrl.value,
  })
);
const whatsappLink = computed(
  () => `https://wa.me/?text=${encodeURIComponent(message.value)}`
);
const fmt = (value, currency) => amount(value, currency, locale.value);
const canChangePixel = computed(() => pixels.value.length > 1);
const pixelChoices = computed(() => [
  ...pixels.value.map(row => {
    const time = relativeTime(row.last_fired_time, locale.value);
    return {
      value: row.id,
      label: row.name,
      hint: time
        ? t('CRM_KANBAN.META_ADS_HUB.ACCOUNT.PIXEL_LAST', { time })
        : t('CRM_KANBAN.META_ADS_HUB.ACCOUNT.PIXEL_NEVER'),
    };
  }),
  {
    value: NO_SITE,
    label: t('CRM_KANBAN.META_ADS_HUB.ACCOUNT.PIXEL_NONE'),
    hint: t('CRM_KANBAN.META_ADS_HUB.ACCOUNT.PIXEL_NONE_HINT'),
  },
]);

// A tela trocou inteira: o foco vai para o título dela, para o leitor de tela anunciar onde a pessoa está.
watch(screen, async () => {
  await nextTick();
  // O passo de destinos é da aba Conexão e não tem o marcador: o foco vai para a pergunta dele.
  const title =
    root.value?.querySelector('[data-conectar-titulo]') ||
    root.value?.querySelector('[data-destinations-title]');
  if (!title) return;
  title.setAttribute('tabindex', '-1');
  title.focus();
});

const go = value => {
  screen.value = value;
};

const destinationSaved = data => {
  savedDestination.value = data;
  go('done');
};
// No celular o aviso nasce abaixo do botão, fora da tela: rola até ele.
const destinationNotSaved = async () => {
  destinationFailed.value = true;
  await nextTick();
  root.value
    ?.querySelector('[data-conectar-escolher-depois]')
    ?.scrollIntoView?.({ block: 'nearest' });
};
const chooseLater = () => {
  destinationLater.value = true;
  go('done');
};
const pageLinked = () => {
  savedDestination.value = { ...savedDestination.value, site_pages_count: 1 };
};

const copy = async text => {
  try {
    await navigator.clipboard.writeText(text);
    copied.value = true;
  } catch {
    // Sem permissão de área de transferência: o texto segue na tela, selecionável.
  }
};

const stopRecheck = () => {
  autoChecking.value = false;
  clearTimeout(recheckTimer);
  recheckTimer = null;
};

const errorText = code =>
  t(errorMessageKey({ response: { data: { error: code } } }), {
    partner: partnerName.value,
  });

const check = async () => {
  stopRecheck();
  errorCode.value = null;
  go('checking');
  try {
    const { data } = await CrmMetaAdsConnectionAPI.adAccounts(mode.value);
    accounts.value = (data.ad_accounts || []).filter(row => row.ready);
  } catch (error) {
    errorCode.value = error?.response?.data?.error || 'generic';
    accounts.value = [];
  }
  if (accounts.value.length === 1) {
    [chosen.value] = accounts.value;
    go('found');
  } else if (accounts.value.length > 1) {
    go('choose');
  } else {
    go('notyet');
    const waitingShare = mode.value === 'partner' && !errorCode.value;
    if (waitingShare && rechecks.value < RECHECK_TIMES) {
      rechecks.value += 1;
      autoChecking.value = true;
      recheckTimer = setTimeout(check, RECHECK_SECONDS * 1000);
    }
  }
};

const checkByHand = () => {
  rechecks.value = 0;
  check();
};

const signIn = async () => {
  loginNotice.value = null;
  mode.value = 'facebook_login';
  try {
    const data = await facebookConnect(facebook.value);
    // Sem código de volta: a pessoa fechou a janela ou o navegador barrou a janela.
    if (data) checkByHand();
    else loginNotice.value = 'popup';
  } catch (error) {
    loginNotice.value = error?.response?.data?.error || 'generic';
  }
};

const startPartner = () => {
  mode.value = 'partner';
  viaSomeone.value = false;
  go('copy');
};

const askSomeone = () => {
  mode.value = 'partner';
  viaSomeone.value = true;
  go('send');
};

const copyAndNext = async () => {
  await copy(partnerId.value);
  go('meta');
};

const openMeta = () => {
  window.open(partnersUrl.value, '_blank', 'noopener,noreferrer');
  go('mark');
};

// Sem a lista de Pixels a conexão vale do mesmo jeito: o "pronto" avisa onde escolher o código depois.
const loadPixels = async account => {
  pickingPixel.value = false;
  try {
    const { data } = await CrmMetaAdsConnectionAPI.pixels(
      mode.value,
      account.id
    );
    pixels.value = data.pixels || [];
    pixelFailed.value = false;
  } catch {
    pixels.value = [];
    pixelFailed.value = true;
  }
};

const save = async ({ noSite = false } = {}) => {
  go('connecting');
  try {
    await CrmMetaAdsConnectionAPI.select({
      mode: mode.value,
      adAccountId: chosen.value.id,
      pixelId: pixel.value?.id || null,
      noSite,
    });
  } catch (error) {
    errorCode.value = error?.response?.data?.error || 'generic';
    go('notyet');
    return;
  }
  // Conta sem destino nenhum ganha o WhatsApp já aqui: quem sair no passo 3 fica como antes (#2054). Se falhar,
  // o passo 3 abre sem nada marcado e só segue com uma escolha gravada.
  if (!chosenDestinations.value) {
    try {
      await CrmMetaAdsConnectionAPI.updateDestinations(WHATSAPP_ONLY);
      preWriteFailed.value = false;
    } catch {
      preWriteFailed.value = true;
    }
  }
  go('destino');
};

const connectAccount = async account => {
  chosen.value = account;
  pixel.value = null;
  go('connecting');
  await loadPixels(account);
  if (pixels.value.length > 1) {
    pixelChoice.value = '';
    go('pixel');
    return;
  }
  pixel.value = pixels.value[0] || null;
  await save();
};

const confirmPixel = () => {
  const noSite = pixelChoice.value === NO_SITE;
  pixel.value = noSite
    ? null
    : pixels.value.find(row => row.id === pixelChoice.value);
  save({ noSite });
};

const openPixelChoice = () => {
  pixelChoice.value = pixel.value?.id || NO_SITE;
  pixelError.value = null;
  pickingPixel.value = true;
};

const changePixel = async () => {
  const noSite = pixelChoice.value === NO_SITE;
  savingPixel.value = true;
  pixelError.value = null;
  try {
    await CrmMetaAdsConnectionAPI.select({
      mode: mode.value,
      adAccountId: chosen.value.id,
      pixelId: noSite ? null : pixelChoice.value,
      noSite,
    });
    pixel.value = noSite
      ? null
      : pixels.value.find(row => row.id === pixelChoice.value);
    pickingPixel.value = false;
  } catch (error) {
    pixelError.value = error?.response?.data?.error || 'generic';
  } finally {
    savingPixel.value = false;
  }
};

const startOver = () => {
  stopRecheck();
  errorCode.value = null;
  if (mode.value === 'facebook_login') go('start');
  else go(viaSomeone.value ? 'send' : 'copy');
};

onMounted(() => {
  // Aberta do meio do painel (o cartão Investimento fica abaixo do herói): a conexão começa no topo.
  root.value?.scrollIntoView?.({ block: 'start' });
  if (hasFacebook.value) preload(facebook.value).catch(() => {});
  if (props.resume?.state === 'choosing') {
    mode.value = props.resume.mode === 'partner' ? 'partner' : 'facebook_login';
    check();
  }
});
onBeforeUnmount(stopRecheck);
</script>

<template>
  <section
    ref="root"
    data-conectar-anuncios
    :data-screen="screen"
    class="mx-auto flex w-full max-w-2xl flex-col gap-6 rounded-2xl bg-n-solid-1 p-5 ring-1 ring-inset ring-n-weak sm:p-8"
  >
    <div
      v-if="canGoBack || partnerStep"
      class="flex flex-wrap items-center justify-between gap-3"
    >
      <button
        v-if="canGoBack"
        type="button"
        data-conectar-voltar
        class="inline-flex min-h-11 items-center gap-1 rounded-xl border-0 bg-transparent px-0 text-sm font-medium text-n-slate-11 hover:text-n-slate-12 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
        @click="emit('back')"
      >
        <span class="i-lucide-arrow-left size-4" aria-hidden="true" />
        {{ $t(`${C}.BACK`) }}
      </button>
      <span
        v-if="partnerStep"
        data-conectar-passo
        class="text-sm font-medium tabular-nums text-n-slate-11"
      >
        {{
          $t(`${C}.STEP_OF`, { step: partnerStep, total: PARTNER_STEPS.length })
        }}
      </span>
    </div>

    <ol
      v-if="facebookStep"
      data-conectar-faixa
      class="m-0 flex list-none items-center gap-2 p-0 text-xs font-medium sm:text-sm"
    >
      <li
        v-for="(item, index) in FACEBOOK_STEPS"
        :key="item"
        class="flex min-w-0 items-center gap-2"
        :aria-current="index + 1 === facebookStep ? 'step' : undefined"
      >
        <span
          class="grid size-6 flex-none place-items-center rounded-full text-xs font-bold"
          :class="
            index + 1 < facebookStep
              ? 'bg-n-teal-9 text-white'
              : index + 1 === facebookStep
                ? 'bg-n-blue-9 text-white'
                : 'bg-n-alpha-2 text-n-slate-11'
          "
        >
          <span
            v-if="index + 1 < facebookStep"
            class="i-lucide-check size-3.5"
            aria-hidden="true"
          />
          <template v-else>{{ index + 1 }}</template>
        </span>
        <span
          class="min-w-0 leading-tight"
          :class="index + 1 === facebookStep ? 'text-n-slate-12' : 'sr-only'"
        >
          {{ $t(`${C}.START.STEPS.${item}`) }}
        </span>
        <span
          v-if="index < FACEBOOK_STEPS.length - 1"
          class="h-px w-4 flex-none bg-n-weak sm:w-8"
          aria-hidden="true"
        />
      </li>
    </ol>

    <!-- Começo: Entrar com o Facebook -->
    <template v-if="screen === 'start'">
      <div class="flex flex-col gap-2">
        <h2
          data-conectar-titulo
          tabindex="-1"
          class="m-0 text-2xl font-bold tracking-tight text-balance text-n-slate-12 outline-none sm:text-3xl"
        >
          {{ $t(`${C}.START.TITLE`) }}
        </h2>
        <p class="m-0 text-base text-n-slate-11">
          {{ $t(`${C}.START.TEXT`) }}
        </p>
      </div>
      <p
        v-if="broken"
        data-conectar-caiu
        class="m-0 rounded-xl bg-n-amber-2 p-4 text-sm text-n-amber-12 ring-1 ring-inset ring-n-amber-6"
      >
        {{ $t(`${C}.START.BROKEN`) }}
      </p>
      <ol
        data-conectar-como
        class="m-0 grid list-none grid-cols-2 gap-2 p-0 sm:grid-cols-4"
        :aria-label="$t(`${C}.START.HOW`)"
      >
        <li
          v-for="(item, index) in FACEBOOK_STEPS"
          :key="item"
          class="flex flex-col items-center gap-2 rounded-2xl bg-n-alpha-1 px-2 py-4 text-center"
        >
          <span
            class="grid size-8 place-items-center rounded-full bg-n-blue-3 text-sm font-bold text-n-blue-11"
          >
            {{ index + 1 }}
          </span>
          <span class="text-sm font-medium leading-tight text-n-slate-12">
            {{ $t(`${C}.START.STEPS.${item}`) }}
          </span>
        </li>
      </ol>
      <div class="flex flex-col gap-3">
        <button
          type="button"
          data-conectar-facebook
          :disabled="isConnecting"
          class="inline-flex min-h-14 w-full items-center justify-center gap-3 rounded-2xl border-0 bg-[#1460D1] px-7 text-base font-semibold text-white hover:bg-[#0F52B8] focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-n-brand disabled:cursor-wait sm:w-auto sm:self-start"
          @click="signIn"
        >
          <span
            class="i-ri-facebook-circle-fill size-6"
            :class="{ 'animate-pulse': isConnecting }"
            aria-hidden="true"
          />
          {{ loginNotice ? $t(`${C}.START.RETRY`) : $t(`${C}.START.CTA`) }}
        </button>
        <p
          v-if="isConnecting"
          role="status"
          class="m-0 rounded-xl bg-n-blue-2 px-4 py-3 text-sm font-medium text-n-blue-11"
        >
          {{ $t(`${C}.START.WAITING`) }}
        </p>
        <div
          v-else-if="loginNotice"
          data-conectar-aviso-login
          role="alert"
          class="flex flex-col gap-2 rounded-xl bg-n-amber-2 p-4 text-sm text-n-amber-12 ring-1 ring-inset ring-n-amber-6"
        >
          <span class="font-semibold">
            {{
              loginNotice === 'popup'
                ? $t(`${C}.START.POPUP_TITLE`)
                : $t(`${C}.START.REFUSED_TITLE`)
            }}
          </span>
          <span>
            {{
              loginNotice === 'popup'
                ? $t(`${C}.START.POPUP_TEXT`)
                : errorText(loginNotice)
            }}
          </span>
        </div>
      </div>
      <ul
        class="m-0 flex list-none flex-wrap gap-x-5 gap-y-2 p-0 text-sm text-n-slate-11"
      >
        <li
          v-for="item in ['SAFE', 'TIME', 'OFF']"
          :key="item"
          class="inline-flex items-center gap-1.5"
        >
          <span
            class="i-lucide-check size-4 text-n-teal-11"
            aria-hidden="true"
          />
          {{ $t(`${C}.TRUST.${item}`) }}
        </li>
      </ul>
      <div
        class="flex flex-wrap gap-x-5 gap-y-1 border-t border-solid border-n-weak pt-4"
      >
        <button
          type="button"
          data-conectar-outra-pessoa
          class="inline-flex min-h-11 items-center gap-1.5 rounded-xl border-0 bg-transparent px-0 text-sm font-medium text-n-blue-11 underline-offset-2 hover:underline focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
          @click="askSomeone"
        >
          <span class="i-lucide-users-round size-4" aria-hidden="true" />
          {{ $t(`${C}.START.SOMEONE`) }}
        </button>
        <button
          v-if="partnerId"
          type="button"
          data-conectar-parceiro
          class="inline-flex min-h-11 items-center gap-1.5 rounded-xl border-0 bg-transparent px-0 text-sm font-medium text-n-slate-11 underline-offset-2 hover:text-n-slate-12 hover:underline focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
          @click="startPartner"
        >
          {{ $t(`${C}.START.PARTNER`) }}
        </button>
      </div>
    </template>

    <!-- Compartilhar como parceiro: 1 de 3 -->
    <template v-else-if="screen === 'copy'">
      <h2
        data-conectar-titulo
        tabindex="-1"
        class="m-0 text-2xl font-bold tracking-tight text-balance text-n-slate-12 outline-none"
      >
        {{ $t(`${C}.COPY.TITLE`, { partner: partnerName }) }}
      </h2>
      <p class="m-0 text-base text-n-slate-11">
        {{ $t(`${C}.COPY.TEXT`) }}
      </p>
      <code
        data-conectar-codigo
        class="select-all self-start rounded-xl bg-n-alpha-1 px-5 py-4 font-mono text-2xl font-semibold tracking-wide text-n-slate-12 tabular-nums"
      >
        {{ partnerId }}
      </code>
      <Button
        data-conectar-copiar
        class="!min-h-12 !rounded-xl self-start"
        icon="i-lucide-copy"
        :label="$t(`${C}.COPY.CTA`)"
        @click="copyAndNext"
      />
    </template>

    <!-- Eu mesmo: 2 de 3 -->
    <template v-else-if="screen === 'meta'">
      <h2
        data-conectar-titulo
        tabindex="-1"
        class="m-0 text-2xl font-bold tracking-tight text-balance text-n-slate-12 outline-none"
      >
        {{ $t(`${C}.META.TITLE`) }}
      </h2>
      <p class="m-0 text-base text-n-slate-11">
        {{ $t(`${C}.META.TEXT`) }}
      </p>
      <MetaTelaGuia kind="partner" :partner-id="partnerId" />
      <div class="flex flex-wrap items-center gap-x-4 gap-y-2">
        <Button
          data-conectar-abrir-meta
          class="!min-h-12 !rounded-xl"
          icon="i-lucide-arrow-up-right"
          :label="$t(`${C}.META.CTA`)"
          @click="openMeta"
        />
        <button
          type="button"
          class="inline-flex min-h-11 items-center gap-1.5 rounded-xl border-0 bg-transparent px-2 text-sm font-medium text-n-slate-11 hover:text-n-slate-12 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
          @click="copy(partnerId)"
        >
          <span class="i-lucide-copy size-4" aria-hidden="true" />
          {{ copied ? $t(`${C}.COPIED`) : $t(`${C}.COPY_AGAIN`) }}
        </button>
      </div>
    </template>

    <!-- Eu mesmo: 3 de 3 -->
    <template v-else-if="screen === 'mark'">
      <h2
        data-conectar-titulo
        tabindex="-1"
        class="m-0 text-2xl font-bold tracking-tight text-balance text-n-slate-12 outline-none"
      >
        {{ $t(`${C}.MARK.TITLE`) }}
      </h2>
      <p class="m-0 text-base text-n-slate-11">
        {{ $t(`${C}.MARK.TEXT`) }}
      </p>
      <MetaTelaGuia kind="assets" :partner-id="partnerId" />
      <div class="flex flex-wrap items-center gap-x-4 gap-y-2">
        <Button
          data-conectar-liberei
          class="!min-h-12 !rounded-xl"
          icon="i-lucide-check"
          :label="$t(`${C}.MARK.CTA`)"
          @click="checkByHand"
        />
        <a
          :href="partnersUrl"
          target="_blank"
          rel="noopener noreferrer"
          class="inline-flex min-h-11 items-center gap-1.5 rounded-xl px-2 text-sm font-medium text-n-slate-11 no-underline hover:text-n-slate-12"
        >
          {{ $t(`${C}.META.AGAIN`) }}
          <span class="i-lucide-arrow-up-right size-4" aria-hidden="true" />
        </a>
      </div>
    </template>

    <!-- Outra pessoa: a mensagem pronta -->
    <template v-else-if="screen === 'send'">
      <h2
        data-conectar-titulo
        tabindex="-1"
        class="m-0 text-2xl font-bold tracking-tight text-balance text-n-slate-12 outline-none"
      >
        {{ $t(`${C}.SEND.TITLE`) }}
      </h2>
      <p class="m-0 text-base text-n-slate-11">
        {{ $t(`${C}.SEND.TEXT`) }}
      </p>
      <p
        data-conectar-mensagem
        class="m-0 whitespace-pre-line rounded-2xl rounded-tl-sm bg-n-teal-2 p-4 text-sm leading-6 text-n-slate-12 ring-1 ring-inset ring-n-teal-5"
      >
        {{ message }}
      </p>
      <div class="flex flex-wrap items-center gap-3">
        <a
          data-conectar-whatsapp
          :href="whatsappLink"
          target="_blank"
          rel="noopener noreferrer"
          class="inline-flex min-h-12 items-center gap-2 rounded-xl bg-n-teal-9 px-5 text-sm font-semibold text-white no-underline transition hover:bg-n-teal-10 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
        >
          <span class="i-lucide-send size-4" aria-hidden="true" />
          {{ $t(`${C}.SEND.WHATSAPP`) }}
        </a>
        <Button
          variant="faded"
          color="slate"
          class="!min-h-12 !rounded-xl"
          icon="i-lucide-copy"
          :label="copied ? $t(`${C}.COPIED`) : $t(`${C}.SEND.COPY`)"
          @click="copy(message)"
        />
      </div>
      <div
        class="flex flex-wrap items-center justify-between gap-3 rounded-2xl bg-n-alpha-1 p-4"
      >
        <span class="text-sm text-n-slate-12">
          {{ $t(`${C}.SEND.AFTER`) }}
        </span>
        <Button
          data-conectar-conferir
          class="!min-h-11 !rounded-xl"
          icon="i-lucide-search-check"
          :label="$t(`${C}.SEND.CHECK`)"
          @click="checkByHand"
        />
      </div>
    </template>

    <!-- Conferindo / conectando -->
    <div
      v-else-if="screen === 'checking' || screen === 'connecting'"
      class="flex flex-col items-center gap-4 py-10 text-center"
      aria-live="polite"
    >
      <Spinner class="size-8 text-n-blue-11" />
      <h2
        data-conectar-titulo
        tabindex="-1"
        class="m-0 text-xl font-semibold text-n-slate-12 outline-none"
      >
        {{
          screen === 'checking'
            ? $t(`${C}.CHECKING`)
            : $t(`${C}.CONNECTING`, { name: chosen?.name })
        }}
      </h2>
    </div>

    <!-- Achou uma conta -->
    <template v-else-if="screen === 'found'">
      <h2
        data-conectar-titulo
        tabindex="-1"
        class="m-0 text-2xl font-bold tracking-tight text-balance text-n-slate-12 outline-none"
      >
        {{ $t(`${C}.FOUND.TITLE`) }}
      </h2>
      <div
        data-conectar-conta
        class="flex flex-wrap items-center gap-4 rounded-2xl p-5 ring-2 ring-inset ring-n-teal-7"
      >
        <span
          class="grid size-12 flex-none place-items-center rounded-xl bg-n-teal-3 text-n-teal-11"
        >
          <span class="i-lucide-megaphone size-6" aria-hidden="true" />
        </span>
        <span class="flex min-w-0 flex-1 flex-col gap-0.5">
          <span class="text-lg font-semibold text-n-slate-12">
            {{ chosen.name }}
          </span>
          <span
            v-if="chosen.spend_30d != null"
            class="text-sm tabular-nums text-n-slate-11"
          >
            {{
              $t(`${C}.SPEND_30D`, {
                value: fmt(chosen.spend_30d, chosen.currency),
              })
            }}
          </span>
        </span>
      </div>
      <Button
        data-conectar-conectar
        class="!min-h-12 !rounded-xl self-start"
        icon="i-lucide-plug"
        :label="$t(`${C}.FOUND.CTA`)"
        @click="connectAccount(chosen)"
      />
    </template>

    <!-- Mais de uma conta: a pessoa escolhe -->
    <template v-else-if="screen === 'choose'">
      <h2
        data-conectar-titulo
        tabindex="-1"
        class="m-0 text-2xl font-bold tracking-tight text-balance text-n-slate-12 outline-none"
      >
        {{ $t(`${C}.CHOOSE.TITLE`) }}
      </h2>
      <p class="m-0 text-base text-n-slate-11">
        {{ $t(`${C}.CHOOSE.TEXT`) }}
      </p>
      <ul class="m-0 flex list-none flex-col gap-3 p-0">
        <li v-for="row in accounts" :key="row.id">
          <button
            type="button"
            :data-conectar-escolher="row.id"
            class="flex min-h-16 w-full flex-wrap items-center gap-x-4 gap-y-1 rounded-2xl border-0 bg-n-solid-1 px-5 py-4 text-start ring-1 ring-inset ring-n-weak transition hover:bg-n-alpha-1 hover:ring-n-blue-7 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
            @click="connectAccount(row)"
          >
            <span class="flex min-w-0 flex-1 flex-wrap items-center gap-2">
              <span class="text-base font-semibold text-n-slate-12">
                {{ row.name }}
              </span>
              <span
                v-if="row.recommended"
                data-conectar-mais-usada
                class="inline-flex items-center rounded-md bg-n-teal-3 px-1.5 py-0.5 text-[11px] font-medium leading-4 text-n-teal-11"
              >
                {{ $t(`${C}.CHOOSE.RECOMMENDED`) }}
              </span>
            </span>
            <span
              v-if="row.spend_30d != null"
              class="text-sm tabular-nums text-n-slate-11"
            >
              {{
                $t(`${C}.SPEND_30D`, {
                  value: fmt(row.spend_30d, row.currency),
                })
              }}
            </span>
            <span
              class="i-lucide-arrow-right size-4 text-n-slate-10"
              aria-hidden="true"
            />
          </button>
        </li>
      </ul>
    </template>

    <!-- Mais de um código do site: a pessoa escolhe -->
    <template v-else-if="screen === 'pixel'">
      <div class="flex flex-col gap-2">
        <h2
          data-conectar-titulo
          tabindex="-1"
          class="m-0 text-2xl font-bold tracking-tight text-balance text-n-slate-12 outline-none"
        >
          {{ $t(`${C}.PIXEL.TITLE`) }}
        </h2>
        <p class="m-0 text-base text-n-slate-11">
          {{ $t(`${C}.PIXEL.TEXT`, { name: chosen?.name }) }}
        </p>
      </div>
      <ChoiceSelect
        v-model="pixelChoice"
        data-conectar-pixel-pergunta
        class="w-full sm:w-auto sm:min-w-80 sm:self-start"
        :options="pixelChoices"
        :placeholder="$t(`${C}.PIXEL.PLACEHOLDER`)"
        :aria-label="$t('CRM_KANBAN.META_ADS_HUB.ACCOUNT.PIXEL_TITLE')"
      />
      <Button
        data-conectar-pixel-continuar
        class="!min-h-12 !rounded-xl self-start"
        icon="i-lucide-plug"
        :disabled="!pixelChoice"
        :label="$t(`${C}.FOUND.CTA`)"
        @click="confirmPixel"
      />
    </template>

    <!-- Ainda não chegou / deu erro -->
    <template v-else-if="screen === 'notyet'">
      <h2
        data-conectar-titulo
        tabindex="-1"
        class="m-0 text-2xl font-bold tracking-tight text-balance text-n-slate-12 outline-none"
      >
        {{
          errorCode ? $t(`${C}.NOT_YET.TITLE_ERROR`) : $t(`${C}.NOT_YET.TITLE`)
        }}
      </h2>
      <p data-conectar-motivo class="m-0 text-base text-n-slate-11">
        {{
          errorCode
            ? errorText(errorCode)
            : $t(
                `${C}.NOT_YET.${mode === 'partner' ? 'TEXT' : 'TEXT_FACEBOOK'}`,
                {
                  partner: partnerName,
                }
              )
        }}
      </p>
      <p
        v-if="autoChecking"
        class="m-0 inline-flex items-center gap-2 text-sm text-n-slate-11"
        aria-live="polite"
      >
        <span
          class="i-lucide-refresh-cw size-4 animate-spin"
          aria-hidden="true"
        />
        {{ $t(`${C}.NOT_YET.AUTO`) }}
      </p>
      <div class="flex flex-wrap items-center gap-3">
        <Button
          data-conectar-de-novo
          class="!min-h-12 !rounded-xl"
          icon="i-lucide-refresh-cw"
          :label="$t(`${C}.NOT_YET.CHECK`)"
          @click="checkByHand"
        />
        <Button
          variant="faded"
          color="slate"
          class="!min-h-12 !rounded-xl"
          icon="i-lucide-list-checks"
          :label="$t(`${C}.NOT_YET.STEPS`)"
          @click="startOver"
        />
      </div>
      <button
        v-if="!viaSomeone"
        type="button"
        class="inline-flex min-h-11 items-center self-start rounded-xl border-0 bg-transparent px-0 text-sm font-medium text-n-blue-11 underline-offset-2 hover:underline focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
        @click="askSomeone"
      >
        {{ $t(`${C}.NOT_YET.ASK_SOMEONE`) }}
      </button>
    </template>

    <!-- Para onde o anúncio leva (#2338): o passo de destinos da aba Conexão -->
    <div v-else-if="screen === 'destino'" class="flex flex-col gap-4">
      <MetaAdsDestinationsStep
        :destinations="destinations"
        :heading-level="2"
        @saved="destinationSaved"
        @failed="destinationNotSaved"
      />
      <p
        v-if="destinationFailed"
        data-conectar-destino-falhou
        role="alert"
        class="m-0 rounded-xl bg-n-ruby-2 p-4 text-sm text-n-ruby-12 ring-1 ring-inset ring-n-ruby-6"
      >
        {{ $t(`${C}.DONE.DESTINATION_NOT_SAVED`) }}
      </p>
      <button
        v-if="destinationFailed"
        type="button"
        data-conectar-escolher-depois
        class="inline-flex min-h-11 items-center self-center rounded-lg border-0 bg-transparent px-3 text-sm font-semibold text-n-blue-11 underline underline-offset-2 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
        @click="chooseLater"
      >
        {{ $t(`${C}.DONE.DESTINATION_LATER`) }}
      </button>
    </div>

    <!-- Pronto -->
    <div
      v-else-if="screen === 'done'"
      class="flex flex-col items-center gap-4 py-6 text-center"
    >
      <span
        class="grid size-16 place-items-center rounded-full bg-n-teal-3 text-n-teal-11"
      >
        <span class="i-lucide-check size-8" aria-hidden="true" />
      </span>
      <h2
        data-conectar-titulo
        tabindex="-1"
        class="m-0 text-2xl font-bold tracking-tight text-balance text-n-slate-12 outline-none"
      >
        {{ $t(`${C}.DONE.TITLE`) }}
      </h2>
      <p class="m-0 max-w-md text-base text-n-slate-11">
        {{ $t(`${C}.DONE.TEXT`, { name: chosen?.name }) }}
      </p>
      <div
        v-if="pixels.length"
        data-conectar-pixel
        class="flex w-full max-w-md flex-col gap-2 rounded-xl bg-n-alpha-1 p-4 text-start"
      >
        <div
          v-if="!pickingPixel"
          class="flex flex-wrap items-center justify-between gap-2"
        >
          <span class="text-sm font-medium text-n-slate-12">
            {{
              pixel
                ? $t('CRM_KANBAN.META_ADS_HUB.ACCOUNT.PIXEL_SUMMARY', {
                    pixel: pixel.name,
                  })
                : $t('CRM_KANBAN.META_ADS_HUB.ACCOUNT.PIXEL_SUMMARY_NONE')
            }}
          </span>
          <button
            v-if="canChangePixel"
            type="button"
            data-conectar-pixel-alterar
            class="inline-flex min-h-11 items-center rounded-lg border-0 bg-transparent px-3 text-sm font-semibold text-n-blue-11 underline underline-offset-2 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
            @click="openPixelChoice"
          >
            {{ $t('CRM_KANBAN.META_ADS_HUB.ACCOUNT.PIXEL_CHANGE') }}
          </button>
        </div>
        <div v-else class="flex flex-wrap items-center gap-2">
          <ChoiceSelect
            v-model="pixelChoice"
            data-conectar-pixel-escolha
            :options="pixelChoices"
            :disabled="savingPixel"
            :aria-label="$t('CRM_KANBAN.META_ADS_HUB.ACCOUNT.PIXEL_TITLE')"
            @change="changePixel"
          />
          <button
            type="button"
            data-conectar-pixel-cancelar
            :disabled="savingPixel"
            class="inline-flex min-h-11 items-center rounded-lg border-0 bg-transparent px-3 text-sm font-medium text-n-slate-11 hover:text-n-slate-12 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
            @click="pickingPixel = false"
          >
            {{
              $t('CRM_KANBAN.META_ADS_HUB.SEM_LOGIN.CONNECT.DONE.PIXEL_CANCEL')
            }}
          </button>
        </div>
        <p
          v-if="pixelError"
          data-conectar-pixel-erro
          role="alert"
          class="m-0 text-sm text-n-ruby-11"
        >
          {{ errorText(pixelError) }}
        </p>
      </div>
      <p
        v-if="pixelFailed"
        data-conectar-pixel-falhou
        class="m-0 max-w-md rounded-xl bg-n-amber-2 p-4 text-sm text-n-amber-12 ring-1 ring-inset ring-n-amber-6"
      >
        {{ $t(`${C}.DONE.PIXEL_FAILED`) }}
      </p>
      <p
        v-if="destinationLater"
        data-conectar-destino-depois
        class="m-0 max-w-md rounded-xl bg-n-amber-2 p-4 text-sm text-n-amber-12 ring-1 ring-inset ring-n-amber-6"
      >
        {{ $t(`${C}.DONE.DESTINATION_LATER_HINT`) }}
      </p>
      <div
        v-if="pageMissing"
        data-conectar-falta-pagina
        class="flex w-full max-w-md flex-wrap items-center justify-between gap-2 rounded-xl bg-n-amber-2 p-4 text-start ring-1 ring-inset ring-n-amber-6"
      >
        <p class="m-0 min-w-0 flex-1 text-sm text-n-amber-12">
          {{ $t(`${C}.DONE.PAGE_MISSING`) }}
        </p>
        <Button
          data-conectar-ligar-pagina
          variant="outline"
          size="sm"
          class="!min-h-11"
          :label="$t(`${C}.DONE.PAGE_LINK`)"
          @click="linkDialog?.open()"
        />
      </div>
      <MetaAdsSiteLinkDialog ref="linkDialog" @created="pageLinked" />
      <Button
        data-conectar-ver-painel
        class="!min-h-12 !rounded-xl"
        icon="i-lucide-arrow-right"
        :label="$t(`${C}.DONE.CTA`)"
        @click="emit('connected')"
      />
    </div>
  </section>
</template>
