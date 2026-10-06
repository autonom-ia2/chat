<script setup>
import { ref, computed, onMounted, onBeforeUnmount } from 'vue';
import { useI18n } from 'vue-i18n';
import QRCode from 'qrcode';
import { useAlert } from 'dashboard/composables';
import WhatsappHybridAPI from 'dashboard/api/whatsappHybrid';
import NextButton from 'dashboard/components-next/button/Button.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';
import Checkbox from 'dashboard/components-next/checkbox/Checkbox.vue';

// Aba "WhatsApp API" da caixa WhatsApp Oficial (chat#1067): a mesma caixa ganha um segundo
// caminho de envio, usado quando a janela oficial de 24 horas está fechada.
const props = defineProps({
  inbox: { type: Object, required: true },
});

const { t } = useI18n();
// eslint-disable-next-line @intlify/vue-i18n/no-dynamic-keys
const tk = (key, params) => t(`INBOX_MGMT.WHATSAPP_HYBRID.${key}`, params);

const ORIGINS = ['human', 'bot', 'automation', 'campaign'];

const state = ref({ status: 'loading' });
const qrDataUrl = ref('');
const pairingCode = ref('');
const isBusy = ref(false);
const rateLimit = ref(20);
let timer = null;

const notConnected = computed(() => state.value.status === 'not_connected');
const connected = computed(() => Boolean(state.value.connected));
const pairing = computed(
  () =>
    !notConnected.value && !connected.value && state.value.status !== 'loading'
);
const wrongNumber = computed(() => connected.value && !state.value.same_number);
const disabledOrigins = computed(() => state.value.disabled_origins || []);

const STATUS_TONES = {
  connected: 'text-n-teal-11 bg-n-teal-3',
  failed: 'text-n-ruby-11 bg-n-ruby-3',
  disconnected: 'text-n-slate-11 bg-n-alpha-2',
};
const statusTone = computed(
  () => STATUS_TONES[state.value.status] || 'text-n-amber-11 bg-n-amber-3'
);
const statusLabel = computed(() => {
  if (notConnected.value) return tk('STATUS.NOT_CONNECTED');
  if (connected.value) return tk('STATUS.CONNECTED');
  if (state.value.status === 'failed') return tk('STATUS.FAILED');
  if (state.value.status === 'disconnected') return tk('STATUS.DISCONNECTED');
  return tk('STATUS.AWAITING');
});

const renderQr = async value => {
  qrDataUrl.value = value
    ? await QRCode.toDataURL(value, { width: 240, margin: 1 }).catch(() => '')
    : '';
};

const apply = async data => {
  state.value = data;
  rateLimit.value = data.rate_limit_per_minute || 20;
  await renderQr(data.qr);
  if (data.connected) pairingCode.value = '';
};

const load = async () => {
  try {
    const { data } = await WhatsappHybridAPI.show(props.inbox.id);
    await apply(data);
  } catch {
    state.value = { status: 'unavailable' };
  }
};

const run = async (action, errorKey) => {
  isBusy.value = true;
  try {
    const response = await action();
    if (response?.data?.status) await apply(response.data);
  } catch {
    useAlert(tk(errorKey));
  } finally {
    isBusy.value = false;
  }
};

const connect = () =>
  run(() => WhatsappHybridAPI.connect(props.inbox.id), 'ERRORS.CONNECT');

const requestCode = () =>
  run(async () => {
    const { data } = await WhatsappHybridAPI.requestCode(props.inbox.id);
    pairingCode.value = data.code;
  }, 'ERRORS.CODE');

const reconnect = () =>
  run(() => WhatsappHybridAPI.reconnect(props.inbox.id), 'ERRORS.CONNECT');

const save = settings =>
  run(
    () => WhatsappHybridAPI.updateSettings(props.inbox.id, settings),
    'ERRORS.SAVE'
  );

const toggleOrigin = (origin, enabled) => {
  const others = disabledOrigins.value.filter(item => item !== origin);
  save({ disabled_origins: enabled ? others : [...others, origin] });
};

const saveRateLimit = () => {
  const value = Math.min(Math.max(parseInt(rateLimit.value, 10) || 1, 1), 120);
  rateLimit.value = value;
  save({ rate_limit_per_minute: value });
};

const disconnect = () =>
  run(async () => {
    await WhatsappHybridAPI.disconnect(props.inbox.id);
    await load();
  }, 'ERRORS.DISCONNECT');

onMounted(() => {
  load();
  timer = setInterval(() => {
    if (pairing.value) load();
  }, 3000);
});

onBeforeUnmount(() => {
  if (timer) clearInterval(timer);
});
</script>

<template>
  <div class="flex flex-col gap-4 py-6">
    <section
      class="flex flex-col gap-4 p-5 border rounded-xl border-n-weak bg-n-solid-1"
    >
      <div class="flex items-center justify-between gap-3">
        <div class="min-w-0">
          <p class="mb-1 text-base font-medium text-n-slate-12">
            {{ tk('TITLE') }}
          </p>
          <p class="mb-0 text-sm text-n-slate-11">{{ tk('DESCRIPTION') }}</p>
        </div>
        <span
          class="inline-flex items-center gap-1 px-2 py-0.5 text-xs font-medium rounded-md shrink-0"
          :class="statusTone"
        >
          <span class="rounded-full size-1.5 bg-current" />
          {{ statusLabel }}
        </span>
      </div>

      <div v-if="notConnected" class="flex">
        <NextButton
          :is-loading="isBusy"
          icon="i-lucide-qr-code"
          :label="tk('CONNECT')"
          @click="connect"
        />
      </div>

      <div
        v-else-if="pairing"
        class="flex flex-col items-center gap-3 px-4 py-6 text-center border rounded-lg border-n-weak"
      >
        <p class="mb-0 text-sm font-medium text-n-slate-12">
          {{ tk('SCAN_TITLE') }}
        </p>
        <div
          class="flex items-center justify-center bg-white rounded-lg size-[240px] p-2"
        >
          <img
            v-if="qrDataUrl"
            :src="qrDataUrl"
            :alt="tk('QR_ALT')"
            class="size-full"
          />
          <span
            v-else
            class="i-lucide-loader-circle animate-spin size-6 text-n-slate-10"
          />
        </div>
        <ol
          class="mb-0 text-xs leading-5 text-left list-decimal list-inside text-n-slate-11"
        >
          <li>{{ tk('STEP_1') }}</li>
          <li>{{ tk('STEP_2') }}</li>
          <li>{{ tk('STEP_3') }}</li>
        </ol>
        <p
          v-if="pairingCode"
          class="mb-0 font-mono text-2xl font-semibold tracking-widest text-n-slate-12"
        >
          {{ pairingCode }}
        </p>
        <p v-if="pairingCode" class="mb-0 text-xs text-n-slate-11">
          {{ tk('CODE_HELP') }}
        </p>
        <div class="flex flex-wrap justify-center gap-2">
          <NextButton
            :is-loading="isBusy"
            color="slate"
            variant="outline"
            size="sm"
            icon="i-lucide-keyboard"
            :label="tk('USE_CODE')"
            @click="requestCode"
          />
          <NextButton
            :is-loading="isBusy"
            color="slate"
            variant="outline"
            size="sm"
            icon="i-lucide-refresh-cw"
            :label="tk('NEW_QR')"
            @click="reconnect"
          />
        </div>
      </div>

      <div
        v-else-if="wrongNumber"
        class="flex items-start gap-2 px-4 py-3 text-sm rounded-lg text-n-ruby-11 bg-n-ruby-3"
      >
        <span class="i-lucide-circle-alert size-4 mt-0.5 shrink-0" />
        {{ tk('WRONG_NUMBER', { phone: state.phone }) }}
      </div>

      <div
        v-else-if="connected"
        class="flex items-center gap-2 px-4 py-3 text-sm rounded-lg text-n-teal-11 bg-n-teal-3"
      >
        <span class="i-lucide-circle-check size-4" />
        {{ tk('CONNECTED_HELP', { phone: state.phone }) }}
      </div>
    </section>

    <section
      v-if="connected && !wrongNumber"
      class="flex flex-col gap-3 p-5 border rounded-xl border-n-weak bg-n-solid-1"
    >
      <p class="mb-0 text-base font-medium text-n-slate-12">
        {{ tk('RISK.TITLE') }}
      </p>
      <label class="flex items-start gap-3 cursor-pointer">
        <Checkbox
          class="mt-0.5"
          :model-value="Boolean(state.risk_accepted)"
          :disabled="isBusy"
          @update:model-value="value => save({ risk_accepted: value })"
        />
        <span class="text-sm text-n-slate-12">{{ tk('RISK.TEXT') }}</span>
      </label>
    </section>

    <section
      v-if="connected && !wrongNumber && state.risk_accepted"
      class="flex flex-col gap-4 p-5 border rounded-xl border-n-weak bg-n-solid-1"
    >
      <div class="flex items-center justify-between gap-3">
        <div>
          <p class="mb-1 text-base font-medium text-n-slate-12">
            {{ tk('ROUTING.TITLE') }}
          </p>
          <p class="mb-0 text-sm text-n-slate-11">
            {{ tk('ROUTING.DESCRIPTION') }}
          </p>
        </div>
        <Switch
          :model-value="Boolean(state.routing_enabled)"
          @update:model-value="value => save({ routing_enabled: value })"
        />
      </div>

      <dl class="grid grid-cols-[1fr_auto] gap-x-6 gap-y-2 mb-0 text-sm">
        <dt class="text-n-slate-11">{{ tk('ROUTING.INSIDE') }}</dt>
        <dd class="mb-0 font-medium text-n-slate-12">{{ tk('OFFICIAL') }}</dd>
        <dt class="text-n-slate-11">{{ tk('ROUTING.OUTSIDE') }}</dt>
        <dd class="mb-0 font-medium text-n-slate-12">
          {{ state.routing_active ? tk('WEB') : tk('OFFICIAL') }}
        </dd>
        <dt class="text-n-slate-11">{{ tk('ROUTING.TEMPLATES') }}</dt>
        <dd class="mb-0 font-medium text-n-slate-12">{{ tk('OFFICIAL') }}</dd>
      </dl>

      <div class="flex flex-col gap-2 pt-3 border-t border-n-weak">
        <p class="mb-0 text-sm font-medium text-n-slate-12">
          {{ tk('ORIGINS.TITLE') }}
        </p>
        <div
          v-for="origin in ORIGINS"
          :key="origin"
          class="flex items-center justify-between gap-3 min-h-[44px]"
        >
          <span class="text-sm text-n-slate-12">
            {{ tk(`ORIGINS.${origin.toUpperCase()}`) }}
          </span>
          <Switch
            :model-value="!disabledOrigins.includes(origin)"
            @update:model-value="value => toggleOrigin(origin, value)"
          />
        </div>
      </div>

      <div
        class="flex flex-wrap items-center justify-between gap-3 pt-3 border-t border-n-weak"
      >
        <label for="hybrid-rate-limit" class="text-sm text-n-slate-12">
          {{ tk('RATE_LIMIT') }}
        </label>
        <input
          id="hybrid-rate-limit"
          v-model="rateLimit"
          type="number"
          min="1"
          max="120"
          class="w-24 px-3 py-2 mb-0 text-sm rounded-lg border border-n-weak bg-n-alpha-black2 text-n-slate-12"
          @change="saveRateLimit"
        />
      </div>
    </section>

    <div v-if="!notConnected && state.status !== 'loading'" class="flex">
      <NextButton
        :is-loading="isBusy"
        color="ruby"
        variant="ghost"
        size="sm"
        icon="i-lucide-unplug"
        :label="tk('DISCONNECT')"
        @click="disconnect"
      />
    </div>
  </div>
</template>
