<script setup>
import { ref, computed, onMounted, onUnmounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import AutonomiaInsuranceAPI from 'dashboard/api/autonomiaInsurance';
import NextButton from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import InsuranceStatusBadge from './InsuranceStatusBadge.vue';
import {
  CONNECTION_STATES,
  asksBrokerAction,
  buildConnection,
  failureMessageKey,
  formatVerifiedAt,
  isConnectedState,
  isTransientState,
  layerRows,
} from '../insuranceContract';

// Aba Conexões (PRD §9) ligada à API real: GET/POST/DELETE /autonomia/insurance/connection.
// A senha sai deste componente uma única vez (no POST) e é zerada na sequência; o backend nunca a
// devolve — a tela só conhece `username_hint`.
const { t } = useI18n();

const connection = ref(buildConnection());
const isLoading = ref(true);
const isBusy = ref(false);
const hasLoadError = ref(false);
const form = ref({ username: '', password: '' });
const formError = ref('');

const status = computed(() => connection.value.status);
const isConnected = computed(() => isConnectedState(status.value));
const showForm = computed(
  () => status.value === CONNECTION_STATES.NOT_CONFIGURED
);
const encryptionUnavailable = computed(
  () => connection.value.encryption_available !== true
);
// Só o que a corretora consegue cotar. O portal devolve ramos que ela não tem habilitados (e às
// vezes sem nome, como `ramo_100`), que não ajudam ninguém na tela. Ficam no `capabilities` gravado,
// para diagnóstico e para o dia em que forem habilitados.
const products = computed(() =>
  (connection.value.capabilities?.products ?? []).filter(item => item.enabled)
);
const hiddenProductCount = computed(
  () =>
    (connection.value.capabilities?.products ?? []).length -
    products.value.length
);

const apply = payload => {
  connection.value = { ...buildConnection(), ...payload };
};

// ACOMPANHA ATÉ ASSENTAR.
//
// A descoberta virou trabalho de fundo porque levava ~25 s e o proxy cortava a requisição. Só que
// sem acompanhar, a tela mostraria "Descobrindo produtos" e ficaria parada nisso até o corretor
// recarregar a página sozinho — trocaríamos um erro visível por um travamento silencioso, que é
// pior.
//
// Consulta de 3 em 3 segundos enquanto o estado for de passagem, com teto. O teto existe porque um
// laço sem fim numa aba esquecida bate no servidor a noite toda; passado ele, a rede de segurança
// do healthcheck é quem resolve.
const INTERVALO_MS = 3000;
const MAXIMO_DE_CONSULTAS = 20;
let acompanhamento = null;

const pararAcompanhamento = () => {
  if (acompanhamento) clearTimeout(acompanhamento);
  acompanhamento = null;
};

const acompanharAteAssentar = (restantes = MAXIMO_DE_CONSULTAS) => {
  pararAcompanhamento();
  if (restantes <= 0 || !isTransientState(connection.value.status)) return;
  acompanhamento = setTimeout(async () => {
    try {
      const { data } = await AutonomiaInsuranceAPI.getConnection();
      apply(data.payload);
    } catch (error) {
      return; // falha de rede não pode virar laço; a próxima ação do corretor reconsulta
    }
    acompanharAteAssentar(restantes - 1);
  }, INTERVALO_MS);
};

const load = async () => {
  isLoading.value = true;
  hasLoadError.value = false;
  try {
    const { data } = await AutonomiaInsuranceAPI.getConnection();
    apply(data.payload);
    // Uma conexão pode estar em estado de passagem quando a tela abre — descoberta disparada de
    // outra aba, ou por alguém do time.
    acompanharAteAssentar();
  } catch (error) {
    hasLoadError.value = true;
  } finally {
    isLoading.value = false;
  }
};

const run = async (request, successKey) => {
  isBusy.value = true;
  try {
    const { data } = await request();
    apply(data.payload);
    acompanharAteAssentar();
    if (successKey) useAlert(t(successKey));
  } catch (error) {
    const message =
      error?.response?.data?.error || t('INSURANCE.CONNECTION.ERRORS.GENERIC');
    useAlert(message);
  } finally {
    isBusy.value = false;
  }
};

const onConnect = async () => {
  formError.value = '';
  const username = form.value.username.trim();
  const password = form.value.password;
  if (!username || !password) {
    formError.value = t('INSURANCE.CONNECTION.FORM.REQUIRED');
    return;
  }
  form.value = { username: '', password: '' };
  await run(
    () => AutonomiaInsuranceAPI.connect({ username, password }),
    'INSURANCE.CONNECTION.ALERTS.CONNECTED'
  );
};

const onReconnect = () =>
  run(
    () => AutonomiaInsuranceAPI.reconnect(),
    'INSURANCE.CONNECTION.ALERTS.RECONNECTED'
  );
const onRescan = () =>
  run(
    () => AutonomiaInsuranceAPI.rescan(),
    'INSURANCE.CONNECTION.ALERTS.RESCANNED'
  );
const onDisconnect = () =>
  run(
    () => AutonomiaInsuranceAPI.removeConnection(),
    'INSURANCE.CONNECTION.ALERTS.DISCONNECTED'
  );

// CRITÉRIO 1.6 — a verificação diz QUANDO e COM QUE evidência.
//
// Isto era `formatRelative`, que mostrava "há 3 minutos". Dois defeitos: o corretor não consegue
// cruzar um tempo relativo com o que ele mesmo viu no portal, e o número cresce sozinho na tela sem
// que nada tenha sido reverificado — a tela envelhece a informação e continua afirmando.
const verifiedLabel = (iso, evidence) => {
  const at = formatVerifiedAt(iso);
  if (!at) return t('INSURANCE.CONNECTION.NOT_VERIFIED');
  const check = String(evidence?.check ?? 'none').toUpperCase();
  return t('INSURANCE.CONNECTION.VERIFIED_AT', {
    at,
    check: t(`INSURANCE.CONNECTION.EVIDENCE.${check}`, ''),
  });
};

const failure = computed(() => connection.value.failure ?? null);
// Só a causa `credential_rejected` chega aqui com `actor: 'broker'`. É a única que pode virar
// pedido de senha — ver o comentário em insuranceContract.js.
const needsBrokerAction = computed(() => asksBrokerAction(failure.value));
// Estados em que a tela DEVE explicar o que houve. `ready` sem falha não explica nada, e estado
// transitório também não — dizer "não identificado" enquanto ainda está autenticando seria alarme
// falso. Uma linha gravada por uma versão anterior chega sem `failure`, e cai no texto genérico:
// nunca no pedido de senha, porque naquela versão `auth_required` também significava sessão morta.
const UNHEALTHY_STATES = [
  CONNECTION_STATES.DEGRADED,
  CONNECTION_STATES.AUTH_REQUIRED,
  CONNECTION_STATES.HUMAN_REQUIRED,
  CONNECTION_STATES.OFFLINE,
];
const failureText = computed(() => {
  if (!failure.value && !UNHEALTHY_STATES.includes(status.value)) return '';
  return t(failureMessageKey(failure.value));
});
const layers = computed(() => layerRows(connection.value.layers));
const pendingInsurers = computed(
  () => connection.value.insurers_pending_auth ?? null
);

const productLabel = item =>
  t(`INSURANCE.PRODUCTS.${String(item.product).toUpperCase()}`, item.product);
const insurerSummary = item => {
  const ready = item.insurers.filter(i => i.enabled).length;
  const pending = item.insurers.filter(
    i => i.integrationStatus === 'auth_required'
  ).length;
  return { ready, pending, total: item.insurers.length };
};

onMounted(load);
onUnmounted(pararAcompanhamento);
</script>

<template>
  <div class="flex flex-col gap-6 max-w-3xl">
    <div
      v-if="isLoading"
      class="flex items-center justify-center py-16 text-n-slate-11"
    >
      <Spinner :size="24" />
    </div>

    <template v-else>
      <div
        v-if="hasLoadError"
        class="flex items-start gap-3 px-4 py-3 rounded-lg bg-n-ruby-2 text-n-ruby-12 text-sm"
      >
        <span class="i-lucide-alert-triangle size-4 mt-0.5 shrink-0" />
        <p>{{ t('INSURANCE.CONNECTION.ERRORS.LOAD') }}</p>
        <NextButton
          ghost
          sm
          :label="t('INSURANCE.CONNECTION.ACTIONS.RETRY')"
          @click="load"
        />
      </div>

      <div
        v-if="encryptionUnavailable"
        class="flex items-start gap-3 px-4 py-3 rounded-lg bg-n-amber-2 text-n-amber-12 text-sm"
      >
        <span class="i-lucide-lock size-4 mt-0.5 shrink-0" />
        <p>{{ t('INSURANCE.CONNECTION.ENCRYPTION_UNAVAILABLE') }}</p>
      </div>

      <section
        class="rounded-xl border border-n-weak bg-n-solid-1 overflow-hidden"
      >
        <header
          class="flex items-center justify-between gap-4 px-5 py-4 border-b border-n-weak"
        >
          <div class="flex items-center gap-3 min-w-0">
            <span
              class="flex items-center justify-center rounded-lg shrink-0 size-9 bg-n-alpha-2 text-n-slate-12"
            >
              <span class="i-lucide-building-2 size-5" />
            </span>
            <div class="flex flex-col min-w-0">
              <h2 class="text-sm font-medium text-n-slate-12">
                {{ t('INSURANCE.CONNECTION.PROVIDER_AGGER') }}
              </h2>
              <p class="text-xs text-n-slate-11 truncate">
                {{ t('INSURANCE.CONNECTION.PROVIDER_AGGER_SUBTITLE') }}
              </p>
            </div>
          </div>
          <InsuranceStatusBadge :state="status" />
        </header>

        <div v-if="showForm" class="flex flex-col gap-4 px-5 py-5">
          <p class="text-sm text-n-slate-11">
            {{ t('INSURANCE.CONNECTION.FORM.INTRO') }}
          </p>
          <div class="grid gap-4 sm:grid-cols-2">
            <Input
              id="insurance-agger-username"
              v-model="form.username"
              type="text"
              autocomplete="off"
              :label="t('INSURANCE.CONNECTION.FORM.USERNAME')"
              :placeholder="t('INSURANCE.CONNECTION.FORM.USERNAME_PLACEHOLDER')"
            />
            <Input
              id="insurance-agger-password"
              v-model="form.password"
              type="password"
              autocomplete="new-password"
              :label="t('INSURANCE.CONNECTION.FORM.PASSWORD')"
              :placeholder="t('INSURANCE.CONNECTION.FORM.PASSWORD_PLACEHOLDER')"
            />
          </div>
          <p v-if="formError" class="text-xs text-n-ruby-11">{{ formError }}</p>
          <p class="text-xs text-n-slate-11">
            {{ t('INSURANCE.CONNECTION.FORM.SECURITY_NOTE') }}
          </p>
          <div>
            <NextButton
              solid
              blue
              icon="i-lucide-plug-zap"
              :label="t('INSURANCE.CONNECTION.ACTIONS.CONNECT')"
              :disabled="isBusy || encryptionUnavailable"
              :is-loading="isBusy"
              @click="onConnect"
            />
          </div>
        </div>

        <div v-else class="flex flex-col gap-5 px-5 py-5">
          <dl class="grid gap-4 sm:grid-cols-2 text-sm">
            <div class="flex flex-col gap-0.5">
              <dt class="text-xs text-n-slate-11">
                {{ t('INSURANCE.CONNECTION.FIELDS.ACCOUNT') }}
              </dt>
              <dd class="text-n-slate-12 text-xs">
                <span class="font-mono">{{
                  connection.username_hint || '—'
                }}</span>
                <span
                  v-if="connection.external_account_label"
                  class="block truncate"
                >
                  {{ connection.external_account_label }}
                </span>
              </dd>
            </div>
            <div class="flex flex-col gap-0.5">
              <dt class="text-xs text-n-slate-11">
                {{ t('INSURANCE.CONNECTION.FIELDS.SESSION') }}
              </dt>
              <dd class="text-n-slate-12">
                {{
                  connection.last_authenticated_at
                    ? t('INSURANCE.CONNECTION.SESSION_AUTHENTICATED')
                    : t('INSURANCE.CONNECTION.SESSION_PENDING')
                }}
              </dd>
            </div>
            <div class="flex flex-col gap-0.5">
              <dt class="text-xs text-n-slate-11">
                {{ t('INSURANCE.CONNECTION.FIELDS.LAST_HEALTHCHECK') }}
              </dt>
              <dd class="text-n-slate-12">
                {{
                  verifiedLabel(
                    connection.evidence?.at || connection.last_healthcheck_at,
                    connection.evidence
                  )
                }}
              </dd>
            </div>
            <div class="flex flex-col gap-0.5">
              <dt class="text-xs text-n-slate-11">
                {{ t('INSURANCE.CONNECTION.FIELDS.LAST_SCAN') }}
              </dt>
              <dd class="text-n-slate-12">
                {{
                  verifiedLabel(connection.last_capability_scan_at, {
                    check: 'capability_scan',
                  })
                }}
              </dd>
            </div>
          </dl>

          <div
            v-if="failureText"
            class="flex items-start gap-2 px-3 py-2 rounded-lg text-xs"
            :class="
              needsBrokerAction
                ? 'bg-n-amber-2 text-n-amber-12'
                : 'bg-n-alpha-2 text-n-slate-12'
            "
          >
            <span
              class="size-4 mt-0.5 shrink-0"
              :class="
                needsBrokerAction ? 'i-lucide-key-round' : 'i-lucide-info'
              "
            />
            <p>{{ failureText }}</p>
          </div>

          <div class="flex flex-wrap items-center gap-2">
            <NextButton
              faded
              slate
              sm
              icon="i-lucide-refresh-cw"
              :label="t('INSURANCE.CONNECTION.ACTIONS.RECONNECT')"
              :disabled="isBusy || isTransientState(status)"
              @click="onReconnect"
            />
            <NextButton
              faded
              slate
              sm
              icon="i-lucide-scan-search"
              :label="t('INSURANCE.CONNECTION.ACTIONS.RESCAN')"
              :disabled="isBusy || !isConnected"
              @click="onRescan"
            />
            <NextButton
              ghost
              ruby
              sm
              icon="i-lucide-unplug"
              :label="t('INSURANCE.CONNECTION.ACTIONS.DISCONNECT')"
              :disabled="isBusy"
              @click="onDisconnect"
            />
          </div>
        </div>
      </section>

      <!-- CRITÉRIO 4.5: o problema de credencial de seguradora aparece AQUI, e nunca na conversa
           com o cliente. -->
      <section
        v-if="pendingInsurers"
        class="flex items-start gap-3 px-4 py-3 rounded-lg bg-n-amber-2 text-n-amber-12 text-sm"
      >
        <span class="i-lucide-key-round size-4 mt-0.5 shrink-0" />
        <div class="flex flex-col gap-1">
          <p class="font-medium">
            {{ t('INSURANCE.CONNECTION.INSURERS_PENDING.TITLE') }}
          </p>
          <p class="text-xs">
            {{
              t('INSURANCE.CONNECTION.INSURERS_PENDING.BODY', {
                count: pendingInsurers.codes?.length ?? 0,
                at: formatVerifiedAt(pendingInsurers.observed_at),
              })
            }}
          </p>
          <p v-if="pendingInsurers.names?.length" class="text-xs font-mono">
            {{ pendingInsurers.names.join(', ') }}
          </p>
        </div>
      </section>

      <!-- CRITÉRIO 1.2: as cinco camadas separadas. `não verificado` é uma resposta, não um vazio. -->
      <section
        v-if="connection.layers"
        class="rounded-xl border border-n-weak bg-n-solid-1 overflow-hidden"
      >
        <header class="px-5 py-4 border-b border-n-weak">
          <h2 class="text-sm font-medium text-n-slate-12">
            {{ t('INSURANCE.CONNECTION.LAYERS.TITLE') }}
          </h2>
          <p class="text-xs text-n-slate-11">
            {{ t('INSURANCE.CONNECTION.LAYERS.SUBTITLE') }}
          </p>
        </header>
        <ul class="divide-y divide-n-weak">
          <li
            v-for="row in layers"
            :key="row.key"
            class="flex items-center justify-between gap-4 px-5 py-2.5 text-sm"
          >
            <span class="text-n-slate-12">
              {{ t(`INSURANCE.CONNECTION.LAYERS.${row.key.toUpperCase()}`) }}
            </span>
            <span
              class="text-xs shrink-0"
              :class="{
                'text-n-teal-11': row.state === 'ok',
                'text-n-ruby-11': row.state === 'failed',
                'text-n-slate-11': row.state === 'unknown',
              }"
            >
              {{
                t(
                  `INSURANCE.CONNECTION.LAYERS.STATE.${row.state.toUpperCase()}`
                )
              }}
            </span>
          </li>
        </ul>
      </section>

      <section
        v-if="isConnected && products.length"
        class="rounded-xl border border-n-weak bg-n-solid-1 overflow-hidden"
      >
        <header class="px-5 py-4 border-b border-n-weak">
          <h2 class="text-sm font-medium text-n-slate-12">
            {{ t('INSURANCE.CAPABILITIES.TITLE') }}
          </h2>
          <p class="text-xs text-n-slate-11">
            {{ t('INSURANCE.CAPABILITIES.SUBTITLE') }}
          </p>
        </header>
        <ul class="divide-y divide-n-weak">
          <li
            v-for="item in products"
            :key="item.product"
            class="flex items-center justify-between gap-4 px-5 py-3 text-sm"
          >
            <div class="flex items-center gap-3 min-w-0">
              <span
                class="size-2 rounded-full shrink-0"
                :class="item.enabled ? 'bg-n-teal-9' : 'bg-n-slate-7'"
              />
              <span class="text-n-slate-12 truncate">
                {{ productLabel(item) }}
                <span
                  v-if="item.labelConfidence === 'inferred'"
                  class="ml-1 text-xs text-n-slate-11"
                  :title="t('INSURANCE.CAPABILITIES.INFERRED_HINT')"
                >
                  *
                </span>
              </span>
            </div>
            <span class="text-xs text-n-slate-11 shrink-0">
              {{
                t('INSURANCE.CAPABILITIES.INSURERS_COUNT', {
                  count: insurerSummary(item).ready,
                })
              }}
              <span v-if="insurerSummary(item).pending">
                ·
                {{
                  t('INSURANCE.CAPABILITIES.PENDING_AUTH', {
                    count: insurerSummary(item).pending,
                  })
                }}
              </span>
            </span>
          </li>
        </ul>
        <p
          v-if="hiddenProductCount"
          class="px-5 py-3 text-xs text-n-slate-11 border-t border-n-weak"
        >
          {{
            t('INSURANCE.CAPABILITIES.HIDDEN_PRODUCTS', {
              count: hiddenProductCount,
            })
          }}
        </p>
      </section>
    </template>
  </div>
</template>
