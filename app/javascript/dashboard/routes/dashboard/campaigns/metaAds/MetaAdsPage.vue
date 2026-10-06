<script setup>
import { computed, onMounted, ref } from 'vue';
import { useRoute, useRouter } from 'vue-router';
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
import { currentStep } from './metaAdsHelpers';

// Campanhas › Anúncios da Meta (#1047, F1b): a conexão guiada num lugar só, em 4 passos —
// conectar, escolher a conta, para onde o anúncio leva, avisar a Meta quando vender. Substitui o
// card "Nomes das campanhas da Meta" de Links e QR codes e o Pixel digitado no funil.
const SALES_STEP = 4;
const DONE = 5;

const connection = ref(null);
const loading = ref(true);
const loadFailed = ref(false);
const started = ref(false);
// Passo aberto pela pessoa ("Alterar", "Ligar", "Conectar de novo") ou o passo da vez.
const openStep = ref(null);
// Modo escolhido no passo 1 antes de a conexão existir (compartilhar ainda não grava nada). Fica no
// endereço (?modo=) para recarregar ou voltar não trocar o caminho em silêncio pela chave antiga (#1068).
const MODES = ['partner', 'token'];
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
const VIEWS = ['resultado', 'conexao'];
const view = ref(
  VIEWS.includes(route.query.aba) ? route.query.aba : 'resultado'
);
const chooseView = value => {
  view.value = value;
  router.replace({ query: { ...route.query, aba: value } });
};
// "Agora não" no passo 4: segue para o resumo, com o passo marcado "Desligado".
const salesLater = ref(false);

const step = computed(() => {
  const value = currentStep(connection.value);
  return value === SALES_STEP && salesLater.value ? DONE : value;
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
const checklistCurrent = computed(() =>
  activeStep.value === 2 && !connection.value?.configured ? 2 : step.value
);
// O painel só existe com a conexão ativa e uma conta de anúncios; sem ele, nem as abas aparecem.
const panelAvailable = computed(
  () =>
    connection.value?.status === 'active' &&
    Boolean(connection.value?.ad_account)
);
const showPanel = computed(
  () => view.value === 'resultado' && panelAvailable.value
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

const accountSaved = data => {
  rememberMode(null);
  update(data);
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
          class="mb-0 text-[1.75rem] font-semibold leading-tight tracking-tight text-n-slate-12"
        >
          {{ $t('CRM_KANBAN.META_ADS_HUB.PAGE.TITLE') }}
        </h1>
        <p class="mt-2 mb-0 text-sm leading-6 text-n-slate-11">
          {{ $t('CRM_KANBAN.META_ADS_HUB.PAGE.SUBTITLE') }}
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

      <MetaAdsHero v-else-if="showHero" @start="started = true" />

      <div
        v-else
        class="grid items-start gap-5 lg:grid-cols-[minmax(0,1fr)_20rem]"
      >
        <div class="flex flex-col min-w-0 gap-5">
          <template v-if="step === 5 && !openStep">
            <div
              v-if="panelAvailable"
              role="group"
              :aria-label="$t('CRM_KANBAN.META_ADS_HUB.PANEL.TABS.LABEL')"
              class="flex gap-1 p-1 rounded-xl bg-n-alpha-1 w-fit"
            >
              <button
                v-for="name in VIEWS"
                :key="name"
                type="button"
                :data-view-tab="name"
                :aria-pressed="(showPanel ? 'resultado' : 'conexao') === name"
                class="px-4 text-sm font-semibold border-0 rounded-lg min-h-11 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
                :class="
                  (showPanel ? 'resultado' : 'conexao') === name
                    ? 'bg-n-solid-1 text-n-slate-12 shadow-sm'
                    : 'bg-transparent text-n-slate-11 hover:text-n-slate-12'
                "
                @click="chooseView(name)"
              >
                {{
                  name === 'resultado'
                    ? $t('CRM_KANBAN.META_ADS_HUB.PANEL.TABS.RESULT')
                    : $t('CRM_KANBAN.META_ADS_HUB.PANEL.TABS.CONNECTION')
                }}
              </button>
            </div>
            <MetaAdsPanel v-if="showPanel" @open="openStep = $event" />
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
            class="p-4 border shadow-sm rounded-2xl border-n-weak bg-n-solid-1 sm:p-6"
          >
            <MetaAdsConnectStep
              v-if="activeStep === 1"
              :connection="connection"
              @partner="startPartner"
              @token="startToken"
            />
            <MetaAdsAccountStep
              v-else-if="activeStep === 2"
              :mode="mode"
              :partner-name="partnerName"
              :current="connection"
              @saved="accountSaved"
              @back="openStep = 1"
            />
            <MetaAdsDestinationsStep
              v-else-if="activeStep === 3"
              :destinations="connection.destinations"
              @saved="update"
            />
            <MetaAdsFunnelStep
              v-else-if="activeStep === 4"
              :connection="connection"
              @finished="finished"
              @later="later"
            />
          </section>
        </div>

        <aside class="order-first lg:order-none lg:sticky lg:top-5">
          <MetaAdsChecklist
            :current="checklistCurrent"
            :open="activeStep <= 4 ? activeStep : null"
            :sales-off="salesOff"
            @change="openStep = $event"
          />
        </aside>
      </div>
    </div>
  </section>
</template>
