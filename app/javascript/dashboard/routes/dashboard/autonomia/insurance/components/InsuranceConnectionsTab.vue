<script setup>
import { ref, computed, onBeforeUnmount } from 'vue';
import { useI18n } from 'vue-i18n';
import NextButton from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import InsuranceStatusBadge from './InsuranceStatusBadge.vue';
import {
  CONNECTION_STATES,
  MOCK_CAPABILITIES,
  buildConnection,
  isConnectedState,
  isTransientState,
  maskUsername,
} from '../insuranceContract';

// Aba Conexões (PRD §9) em modo contract-first: os estados, textos e ações são os finais;
// a transição entre estados é simulada localmente até o connector existir (Onda 3, #295).
// A senha digitada NUNCA sai deste componente nem fica em memória após o submit.
const { t } = useI18n();

const MOCK_STEP_MS = 700;

const connection = ref(buildConnection());
const form = ref({ username: '', password: '' });
const formError = ref('');
const timers = [];

const isConnected = computed(() => isConnectedState(connection.value.status));
const isBusy = computed(() => isTransientState(connection.value.status));
const showForm = computed(
  () => connection.value.status === CONNECTION_STATES.NOT_CONFIGURED
);

const later = (fn, delay) => {
  const id = setTimeout(fn, delay);
  timers.push(id);
};

const now = () => new Date().toISOString();

const runMockConnection = usernameHint => {
  connection.value = buildConnection({
    status: CONNECTION_STATES.PROVISIONING,
    username_hint: usernameHint,
  });
  later(() => {
    connection.value.status = CONNECTION_STATES.AUTHENTICATING;
  }, MOCK_STEP_MS);
  later(() => {
    connection.value.status = CONNECTION_STATES.DISCOVERING;
    connection.value.last_authenticated_at = now();
  }, MOCK_STEP_MS * 2);
  later(() => {
    connection.value.status = CONNECTION_STATES.READY;
    connection.value.last_healthcheck_at = now();
    connection.value.last_capability_scan_at = now();
    connection.value.capabilities = [...MOCK_CAPABILITIES];
  }, MOCK_STEP_MS * 3);
};

const onConnect = () => {
  formError.value = '';
  const username = form.value.username.trim();
  if (!username || !form.value.password) {
    formError.value = t('INSURANCE.CONNECTION.FORM.REQUIRED');
    return;
  }
  const hint = maskUsername(username);
  form.value = { username: '', password: '' };
  runMockConnection(hint);
};

const onReconnect = () => {
  if (isBusy.value) return;
  runMockConnection(connection.value.username_hint);
};

const onRescan = () => {
  if (isBusy.value || !isConnected.value) return;
  connection.value.status = CONNECTION_STATES.DISCOVERING;
  later(() => {
    connection.value.status = CONNECTION_STATES.READY;
    connection.value.last_capability_scan_at = now();
    connection.value.last_healthcheck_at = now();
  }, MOCK_STEP_MS);
};

const onDisconnect = () => {
  connection.value = buildConnection();
};

const formatRelative = iso => {
  if (!iso) return t('INSURANCE.CONNECTION.NEVER');
  const diffMin = Math.max(0, Math.round((Date.now() - new Date(iso)) / 60000));
  if (diffMin < 1) return t('INSURANCE.CONNECTION.JUST_NOW');
  return t('INSURANCE.CONNECTION.MINUTES_AGO', { count: diffMin });
};

const productLabel = product =>
  t(`INSURANCE.PRODUCTS.${product.toUpperCase()}`);

onBeforeUnmount(() => timers.forEach(clearTimeout));
</script>

<template>
  <div class="flex flex-col gap-6 max-w-3xl">
    <div
      class="flex items-start gap-3 px-4 py-3 rounded-lg bg-n-amber-2 text-n-amber-12 text-sm"
    >
      <span class="i-lucide-flask-conical size-4 mt-0.5 shrink-0" />
      <p>{{ t('INSURANCE.CONNECTION.MOCK_NOTICE') }}</p>
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
        <InsuranceStatusBadge :state="connection.status" />
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
            <dd class="text-n-slate-12 font-mono text-xs">
              {{ connection.username_hint || '—' }}
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
              {{ formatRelative(connection.last_healthcheck_at) }}
            </dd>
          </div>
          <div class="flex flex-col gap-0.5">
            <dt class="text-xs text-n-slate-11">
              {{ t('INSURANCE.CONNECTION.FIELDS.LAST_SCAN') }}
            </dt>
            <dd class="text-n-slate-12">
              {{ formatRelative(connection.last_capability_scan_at) }}
            </dd>
          </div>
        </dl>

        <div class="flex flex-wrap items-center gap-2">
          <NextButton
            faded
            slate
            sm
            icon="i-lucide-refresh-cw"
            :label="t('INSURANCE.CONNECTION.ACTIONS.RECONNECT')"
            :disabled="isBusy"
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

    <section
      v-if="isConnected"
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
          v-for="item in connection.capabilities"
          :key="item.product"
          class="flex items-center justify-between gap-4 px-5 py-3 text-sm"
        >
          <div class="flex items-center gap-3 min-w-0">
            <span
              class="size-2 rounded-full shrink-0"
              :class="item.enabled ? 'bg-n-teal-9' : 'bg-n-slate-7'"
            />
            <span class="text-n-slate-12 truncate">
              {{ productLabel(item.product) }}
            </span>
          </div>
          <span class="text-xs text-n-slate-11 shrink-0">
            {{
              item.enabled
                ? t('INSURANCE.CAPABILITIES.INSURERS_COUNT', {
                    count: item.insurers.length,
                  })
                : t('INSURANCE.CAPABILITIES.NOT_ENABLED')
            }}
          </span>
        </li>
      </ul>
    </section>
  </div>
</template>
