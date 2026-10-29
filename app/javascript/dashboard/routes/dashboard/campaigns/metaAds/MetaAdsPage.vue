<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { usePermissionGranted } from 'dashboard/composables/useCanManage';
import { META_ADS_MANAGE_PERMISSION } from 'dashboard/constants/permissions';
import { useMapGetter } from 'dashboard/composables/store';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import CrmMetaAdsConnectionAPI from 'dashboard/api/crmMetaAdsConnection';
import MetaAdsHero from './components/MetaAdsHero.vue';
import MetaAdsChecklist from './components/MetaAdsChecklist.vue';
import MetaAdsConnectStep from './components/MetaAdsConnectStep.vue';
import MetaAdsAccountStep from './components/MetaAdsAccountStep.vue';
import MetaAdsDestinationsStep from './components/MetaAdsDestinationsStep.vue';
import MetaAdsFunnelStep from './components/MetaAdsFunnelStep.vue';
import MetaAdsSummary from './components/MetaAdsSummary.vue';
import MetaAdsPanel from './components/MetaAdsPanel.vue';
import AnunciosSemLogin from './semLogin/AnunciosSemLogin.vue';
import MetaAdsOrganic from './organico/MetaAdsOrganic.vue';
import MetaAdsViewTabs from './components/MetaAdsViewTabs.vue';
import MetaAdsLeadForms from './leadForms/MetaAdsLeadForms.vue';
import { currentStep } from './metaAdsHelpers';

// Campanhas › Anúncios da Meta (#1047, F1b): a conexão guiada num lugar só, em 4 passos —
// conectar, escolher a conta, para onde o anúncio leva, avisar a Meta quando vender. Substitui o
// card "Nomes das campanhas da Meta" de Links e QR codes e o Pixel digitado no funil.
const SALES_STEP = 4;
const DONE = 5;
// Conectar, configurar e desconectar: administrador ou meta_ads_manage (#2070). Quem chega só com meta_ads_view
// (#1794) vê só o painel; sem conexão, a tela diz a quem pedir.
const canManageMetaAds = usePermissionGranted(META_ADS_MANAGE_PERMISSION);
const readOnly = computed(() => !canManageMetaAds.value);

const connection = ref(null);
const loading = ref(true);
const loadFailed = ref(false);
const started = ref(false);
// Passo aberto pela pessoa ("Alterar", "Ligar", "Conectar de novo") ou o passo da vez.
const openStep = ref(null);
// Modo escolhido no passo 1 antes de a conexão existir (compartilhar ainda não grava nada). Fica no
// endereço (?modo=) para recarregar ou voltar não trocar o caminho em silêncio pela chave antiga (#1068).
const MODES = ['partner', 'token', 'facebook_login'];
const route = useRoute();
const router = useRouter();
const chosenMode = ref(
  MODES.includes(route.query.modo) ? route.query.modo : null
);
const rememberMode = value => {
  chosenMode.value = value;
  const query = { ...route.query };
  if (value) query.modo = value;
  else delete query.modo;
  router.replace({ query });
};
// Conectado (#1088): "Resultado" (o painel do dia a dia) ou "Conexão" (o resumo da conexão), lembrado no
// endereço (?aba=). Conexão que precisa de atenção abre direto na conexão.
// "Orgânico" (#2199) só com a flag meta_ads_organico: o que a Página e o Instagram alcançam sem anúncio.
// Formulários (#2195) só com a flag meta_ads_formularios: quem preenche o formulário do anúncio entra no funil.
const ALL_VIEWS = ['resultado', 'organico', 'formularios', 'conexao'];
const { t } = useI18n();
const tabLabels = computed(() => ({
  resultado: t('CRM_KANBAN.META_ADS_HUB.PANEL.TABS.RESULT'),
  organico: t('META_ADS_ORGANIC.TAB'),
  formularios: t('CRM_KANBAN.META_ADS_HUB.PANEL.TABS.LEAD_FORMS'),
  conexao: t('CRM_KANBAN.META_ADS_HUB.PANEL.TABS.CONNECTION'),
}));
const view = ref(
  ALL_VIEWS.includes(route.query.aba) ? route.query.aba : 'resultado'
);
// A aba segue o endereço: quem manda para a Conexão de dentro do Resultado (criar anúncio sem conta, sem Página) só
// muda o `?aba=`.
watch(
  () => route.query.aba,
  aba => {
    if (ALL_VIEWS.includes(aba)) view.value = aba;
  }
);
// Trocar de aba encerra a volta pendente (`?volta=`): escolher a conta depois não leva mais à criação nem ao anúncio.
const chooseView = value => {
  view.value = value;
  const { volta, ...query } = route.query;
  router.replace({ query: { ...query, aba: value } });
};
const isFeatureEnabledonAccount = useMapGetter(
  'accounts/isFeatureEnabledonAccount'
);
// "Agora não" no passo 4: segue para o resumo, com o passo marcado "Desligado".
const salesLater = ref(false);

// Com Anúncios sem login (#2054), avisar a Meta das vendas é opcional: quem conectou para ver o gasto vai direto ao
// painel, e o passo fica "Desligado" na Conexão, com o botão para ligar.
const salesOptional = computed(
  () =>
    salesLater.value ||
    isFeatureEnabledonAccount.value(
      Number(route.params.accountId),
      FEATURE_FLAGS.ANUNCIOS_SEM_LOGIN
    )
);
const step = computed(() => {
  const value = currentStep(connection.value);
  return value === SALES_STEP && salesOptional.value ? DONE : value;
});
const salesOff = computed(
  () => step.value === DONE && !connection.value?.sales_signal?.enabled
);
const activeStep = computed(() => {
  if (openStep.value) return openStep.value;
  if (step.value === 2 && !connection.value?.configured && !chosenMode.value) {
    return 1;
  }
  // Caminho escolhido diferente do gravado (ex.: trocar a chave antiga pelo compartilhamento): a
  // conta é escolhida de novo por esse caminho, mesmo depois de recarregar.
  const switching =
    chosenMode.value &&
    connection.value?.configured &&
    chosenMode.value !== connection.value.mode;
  return switching ? 2 : step.value;
});
const mode = computed(
  () => chosenMode.value || connection.value?.mode || 'partner'
);
const partnerName = computed(
  () => connection.value?.partner?.business_name || 'Hub2You'
);
// Compartilhar escolhido e conexão ainda não gravada: o passo 1 já conta como feito.
// Conta gravada sem código do site e sem "Não tenho site": o passo da conta fica pendente, não feito (#2343).
const accountPending = computed(
  () =>
    Boolean(connection.value?.ad_account) &&
    !connection.value?.pixel &&
    !connection.value?.no_site
);
// Anúncio levando ao site sem página do site ligada (#2338): o passo do Destino fica pendente, não feito.
const destinationsPending = computed(
  () =>
    Boolean(connection.value?.destinations?.site) &&
    connection.value?.site_pages_count === 0
);
const checklistCurrent = computed(() =>
  activeStep.value === 2 && !connection.value?.configured ? 2 : step.value
);
// O painel só existe com a conexão ativa e uma conta de anúncios; sem ele, nem as abas aparecem.
const panelAvailable = computed(
  () =>
    connection.value?.status === 'active' &&
    Boolean(connection.value?.ad_account)
);
// Seus posts virou página própria (#2302): com a flag seus_posts, a aba sai daqui e o endereço antigo (?aba=organico,
// de links e da volta do login do Instagram) leva à página nova, para quem pode abri-la.
const seusPostsOn = computed(() =>
  isFeatureEnabledonAccount.value(
    Number(route.params.accountId),
    FEATURE_FLAGS.SEUS_POSTS
  )
);
const canSeePosts = usePermissionGranted('posts_view');
const canManagePosts = usePermissionGranted('posts_manage');
// As flags da conta podem chegar depois da tela montar (link direto): a troca espera por elas.
watch(
  () =>
    route.query.aba === 'organico' &&
    seusPostsOn.value &&
    (canSeePosts.value || canManagePosts.value),
  mover => {
    if (mover)
      router.replace({
        name: 'seus_posts_index',
        params: { accountId: route.params.accountId },
      });
  },
  { immediate: true }
);
// A aba antiga só sai para quem abre a página nova: quem só tem Anúncios da Meta continua com ela.
const organicOn = computed(
  () =>
    !(seusPostsOn.value && (canSeePosts.value || canManagePosts.value)) &&
    isFeatureEnabledonAccount.value(
      Number(route.params.accountId),
      FEATURE_FLAGS.META_ADS_ORGANICO
    )
);
const leadFormsOn = computed(() =>
  isFeatureEnabledonAccount.value(
    Number(route.params.accountId),
    FEATURE_FLAGS.META_ADS_FORMULARIOS
  )
);
// Quem só vê (meta_ads_view) fica sem a Conexão: as abas dele são Resultado, Seus posts e Formulários.
const VIEWS = computed(() =>
  ALL_VIEWS.filter(
    name =>
      (name !== 'organico' || organicOn.value) &&
      (name !== 'formularios' || leadFormsOn.value) &&
      (name !== 'conexao' || !readOnly.value)
  )
);
// Aba que a tela mostra: sem painel, só a Conexão; aba fora da lista (flag desligada), o Resultado.
const activeView = computed(() => {
  if (!panelAvailable.value) return 'conexao';
  return VIEWS.value.includes(view.value) ? view.value : 'resultado';
});
const showPanel = computed(() => activeView.value === 'resultado');
const showOrganic = computed(() => activeView.value === 'organico');
const showLeadForms = computed(() => activeView.value === 'formularios');
// Na aba Seus posts o subtítulo fala de post, não de anúncio.
const subtitle = computed(() =>
  showOrganic.value && !openStep.value
    ? t('META_ADS_ORGANIC.SUBTITLE')
    : t('CRM_KANBAN.META_ADS_HUB.PAGE.SUBTITLE')
);
// Painel conectado (#2054): a lista dos 4 passos sai da lateral do Resultado e o painel usa a largura toda. Ela
// aparece na aba Conexão e enquanto um passo está aberto ou falta configurar.
const showChecklist = computed(
  () =>
    !(
      step.value === DONE &&
      !openStep.value &&
      (showPanel.value || showOrganic.value || showLeadForms.value)
    )
);
// Anúncios sem login (#1960, degrau 0): com a flag e sem conexão de anúncios nenhuma (o servidor diz em
// whatsapp_result.enabled), a página abre pronta com o resultado que chega pelo WhatsApp. Quem já tem
// conexão (ativa, caída ou no meio da escolha) segue no caminho de sempre, com "Conectar de novo".
const semLogin = computed(
  () =>
    isFeatureEnabledonAccount.value(
      Number(route.params.accountId),
      FEATURE_FLAGS.ANUNCIOS_SEM_LOGIN
    ) && Boolean(connection.value?.whatsapp_result?.enabled)
);
const showHero = computed(
  () => !connection.value?.configured && !started.value
);

const load = async () => {
  loading.value = true;
  loadFailed.value = false;
  try {
    const { data } = await CrmMetaAdsConnectionAPI.get();
    connection.value = data;
  } catch {
    loadFailed.value = true;
  } finally {
    loading.value = false;
  }
};

const update = data => {
  connection.value = { ...connection.value, ...data };
  openStep.value = null;
};

const startPartner = () => {
  rememberMode('partner');
  openStep.value = 2;
};

// A chave colada já foi testada e salva pelo diálogo; a conexão é relida antes de listar as contas.
const startToken = async () => {
  rememberMode('token');
  await load();
  if (!loadFailed.value) openStep.value = 2;
};

// "Entrar com o Facebook" (#1069): o servidor já trocou o código, testou e gravou a conexão.
const startFacebookLogin = data => {
  rememberMode('facebook_login');
  update(data);
  openStep.value = 2;
};

// Entrou de novo com o Facebook a partir dos comentários de um anúncio (#2197, `?volta=<anúncio>`): volta ao anúncio.
// Veio de criar anúncio sem conta de anúncios (#2338, `?volta=criar`): volta para criar.
const backToAd = () => {
  const target = route.query.volta;
  if (!target) return;
  view.value = 'resultado';
  const back = target === 'criar' ? { criar: 'novo' } : { anuncio: target };
  router.replace({ query: { aba: 'resultado', ...back } });
};

const accountSaved = data => {
  rememberMode(null);
  update(data);
  backToAd();
};

// Passo 4 gravado no funil: relê a conexão, que diz se as vendas já são avisadas.
const finished = async () => {
  salesLater.value = false;
  openStep.value = null;
  await load();
};

const later = () => {
  salesLater.value = true;
  openStep.value = null;
};

// Conectado a partir do painel sem login (#2054): direto para o painel com gasto.
const connectedFromWhatsapp = async () => {
  chooseView('resultado');
  await load();
};

// Com a conexão já gravada, o passo na tela que não é o da vez (aberto por "Alterar", ou a troca de caminho que
// voltou do endereço ?modo= depois de recarregar) ganha "Voltar": fecha o passo, desfaz o caminho escolhido pela
// metade e volta ao passo da vez — com tudo feito, à aba em que a pessoa estava. O passo da vez não tem "Voltar":
// fechá-lo voltaria a ele mesmo.
const canGoBack = computed(
  () =>
    activeStep.value <= SALES_STEP &&
    activeStep.value !== step.value &&
    Boolean(connection.value?.configured)
);
const goBack = () => {
  rememberMode(null);
  openStep.value = null;
};

const reconnect = () => {
  started.value = true;
  openStep.value = 1;
};

const removed = async () => {
  rememberMode(null);
  started.value = false;
  salesLater.value = false;
  openStep.value = null;
  await load();
};

// Criar anúncio achou a conexão sem conta de anúncios (#2338): a conexão em memória está velha (o login refeito na
// criação limpou a escolha). Relê, e a Conexão abre no passo da conta.
watch(
  () => route.query.volta,
  target => {
    if (target === 'criar') load();
  }
);

onMounted(load);
</script>

<template>
  <section
    class="flex flex-col w-full h-full min-w-0 overflow-y-auto bg-n-slate-2"
  >
    <div class="mx-auto w-full max-w-[90rem] p-4 sm:p-5 lg:p-8">
      <nav
        class="flex flex-wrap items-center gap-2 mb-5 text-xs text-n-slate-11"
        :aria-label="$t('CRM_KANBAN.META_ADS_HUB.PAGE.BREADCRUMB')"
      >
        {{ $t('CRM_KANBAN.META_ADS_HUB.PAGE.GROUP') }}
        <span class="i-lucide-chevron-right size-3.5" aria-hidden="true" />
        <span class="font-medium text-n-blue-11" aria-current="page">
          {{ $t('CRM_KANBAN.META_ADS_HUB.PAGE.TITLE') }}
        </span>
      </nav>
      <header class="mb-6">
        <h1
          class="mb-0 font-interDisplay text-[1.875rem] font-520 leading-tight tracking-[-0.02em] text-n-slate-12"
        >
          {{ $t('CRM_KANBAN.META_ADS_HUB.PAGE.TITLE') }}
        </h1>
        <p class="mt-2 mb-0 text-sm leading-6 text-n-slate-11">
          {{ subtitle }}
        </p>
      </header>

      <div v-if="loading && !connection" class="flex justify-center p-12">
        <Spinner />
      </div>

      <div
        v-else-if="loadFailed"
        role="alert"
        class="flex flex-col items-start gap-3 p-6 border shadow-sm rounded-2xl border-n-weak bg-n-solid-1"
      >
        <p class="m-0 text-sm text-n-ruby-11">
          {{ $t('CRM_KANBAN.META_ADS_HUB.PAGE.LOAD_ERROR') }}
        </p>
        <Button
          size="sm"
          icon="i-lucide-refresh-cw"
          class="!min-h-11 !rounded-xl"
          :label="$t('CRM_KANBAN.META_ADS_HUB.PAGE.RETRY')"
          @click="load"
        />
      </div>

      <AnunciosSemLogin
        v-else-if="semLogin"
        :result="connection.whatsapp_result"
        :connection="connection"
        :read-only="readOnly"
        @connected="connectedFromWhatsapp"
      />

      <template v-else-if="readOnly">
        <div v-if="panelAvailable" class="flex flex-col min-w-0 gap-5">
          <MetaAdsViewTabs
            v-if="VIEWS.length > 1"
            :views="VIEWS"
            :active="activeView"
            :labels="tabLabels"
            @choose="chooseView"
          />
          <MetaAdsOrganic v-if="showOrganic" read-only />
          <MetaAdsLeadForms v-else-if="showLeadForms" read-only />
          <MetaAdsPanel v-else read-only />
        </div>
        <div
          v-else
          data-meta-ads-not-connected
          class="flex flex-col gap-2 p-6 border border-solid shadow-sm rounded-2xl border-n-weak bg-n-solid-1"
        >
          <h2 class="m-0 text-base font-520 text-n-slate-12">
            {{ $t('CRM_KANBAN.META_ADS_HUB.PAGE.NOT_CONNECTED_TITLE') }}
          </h2>
          <p class="m-0 text-sm leading-6 text-n-slate-11">
            {{ $t('CRM_KANBAN.META_ADS_HUB.PAGE.NOT_CONNECTED_TEXT') }}
          </p>
        </div>
      </template>

      <MetaAdsHero v-else-if="showHero" @start="started = true" />

      <div
        v-else
        class="grid items-start gap-5"
        :class="{ 'lg:grid-cols-[minmax(0,1fr)_20rem]': showChecklist }"
      >
        <div class="flex flex-col min-w-0 gap-5">
          <template v-if="step === 5 && !openStep">
            <MetaAdsViewTabs
              v-if="panelAvailable"
              :views="VIEWS"
              :active="activeView"
              :labels="tabLabels"
              @choose="chooseView"
            />
            <MetaAdsPanel v-if="showPanel" @open="openStep = $event" />
            <MetaAdsOrganic v-else-if="showOrganic" :read-only="readOnly" />
            <MetaAdsLeadForms
              v-else-if="showLeadForms"
              :read-only="readOnly"
              @connect="chooseView('conexao')"
            />
            <MetaAdsSummary
              v-else
              :connection="connection"
              @removed="removed"
              @reconnect="reconnect"
              @open="openStep = $event"
            />
          </template>

          <section
            v-if="activeStep <= 4"
            class="flex flex-col gap-4 p-5 border border-solid rounded-xl border-n-weak bg-n-solid-1 sm:p-6"
          >
            <button
              v-if="canGoBack"
              type="button"
              data-meta-ads-step-back
              class="inline-flex items-center self-start gap-1 px-0 text-sm font-medium bg-transparent border-0 rounded-xl min-h-11 text-n-slate-11 hover:text-n-slate-12 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
              @click="goBack"
            >
              <span class="i-lucide-arrow-left size-4" aria-hidden="true" />
              {{ $t('CRM_KANBAN.META_ADS_HUB.PAGE.BACK') }}
            </button>
            <MetaAdsConnectStep
              v-if="activeStep === 1"
              :connection="connection"
              @partner="startPartner"
              @token="startToken"
              @facebook-login="startFacebookLogin"
            />
            <MetaAdsAccountStep
              v-else-if="activeStep === 2"
              :mode="mode"
              :partner-name="partnerName"
              :current="connection"
              :show-back="!canGoBack"
              @saved="accountSaved"
              @back="openStep = 1"
            />
            <MetaAdsDestinationsStep
              v-else-if="activeStep === 3"
              :destinations="connection.destinations"
              @saved="update"
              @page-linked="load"
            />
            <MetaAdsFunnelStep
              v-else-if="activeStep === 4"
              :connection="connection"
              @finished="finished"
              @later="later"
            />
          </section>
        </div>

        <aside
          v-if="showChecklist"
          class="order-first lg:order-none lg:sticky lg:top-5"
        >
          <MetaAdsChecklist
            :current="checklistCurrent"
            :open="activeStep <= 4 ? activeStep : null"
            :sales-off="salesOff"
            :account-pending="accountPending"
            :destinations-pending="destinationsPending"
            @change="openStep = $event"
          />
        </aside>
      </div>
    </div>
  </section>
</template>
