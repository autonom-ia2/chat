<script setup>
import { ref, computed, onMounted, onBeforeUnmount } from 'vue';
import { useI18n } from 'vue-i18n';
import QRCode from 'qrcode';
import { useAlert } from 'dashboard/composables';
import WhatsappHybridAPI from 'dashboard/api/whatsappHybrid';
import NextButton from 'dashboard/components-next/button/Button.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';
import Checkbox from 'dashboard/components-next/checkbox/Checkbox.vue';
import { qrSecondsLeft, formatSeconds } from 'dashboard/helper/wahaQrWindow';

// Aba "WhatsApp API" da caixa WhatsApp Oficial (chat#1067): a mesma caixa ganha um segundo
// caminho de envio, usado quando a janela oficial de 24 horas está fechada.
const props = defineProps({
  inbox: { type: Object, required: true },
});

const { t } = useI18n();
// eslint-disable-next-line @intlify/vue-i18n/no-dynamic-keys
const tk = (key, params) => t(`INBOX_MGMT.WHATSAPP_HYBRID.${key}`, params);
// Mesmos textos de QR expirado/desconectado da caixa WhatsApp API.
// eslint-disable-next-line @intlify/vue-i18n/no-dynamic-keys
const tw = (key, params) => t(`INBOX_MGMT.WAHA_CONNECTION.${key}`, params);

const ORIGINS = ['human', 'bot', 'automation', 'campaign'];

const state = ref({ status: 'loading' });
const qrDataUrl = ref('');
const pairingCode = ref('');
const isBusy = ref(false);
const rateLimit = ref(20);
// Posição do QR atual na rodada de pareamento (1..6) e quando ele apareceu.
const qrValue = ref('');
const qrIndex = ref(0);
const qrShownAt = ref(0);
const now = ref(Date.now());
let timer = null;
let clock = null;
let ticks = 0;

const notConnected = computed(() => state.value.status === 'not_connected');
const connected = computed(() => Boolean(state.value.connected));
// FAILED (rodada de QR esgotada) e STOPPED: nenhum QR novo chega sem reiniciar.
const isExpired = computed(() =>
  ['failed', 'disconnected'].includes(state.value.status)
);
const stoppedKey = computed(() =>
  state.value.status === 'disconnected' ? 'DISCONNECTED' : 'EXPIRED'
);
const pairing = computed(
  () =>
    !notConnected.value &&
    !connected.value &&
    !isExpired.value &&
    !['loading', 'unavailable'].includes(state.value.status)
);
const timeLeft = computed(() => {
  if (!qrIndex.value || !qrDataUrl.value) return '';
  const elapsed = Math.max(now.value - qrShownAt.value, 0) / 1000;
  return formatSeconds(qrSecondsLeft(qrIndex.value, elapsed));
});
const wrongNumber = computed(() => connected.value && !state.value.same_number);
const disabledOrigins = computed(() => state.value.disabled_origins || []);

// Limite de conversas novas do WhatsApp (NONE, FIRST_WARNING, SECOND_WARNING, CAPPED).
const capping = computed(() => state.value.capping || { status: 'NONE' });
const cappingKey = computed(() => {
  const keys = {
    FIRST_WARNING: 'NEAR',
    SECOND_WARNING: 'NEAR',
    CAPPED: 'BLOCKED',
  };
  return keys[capping.value.status] || '';
});
const cappingEnd = computed(() =>
  capping.value.cycle_end
    ? new Date(capping.value.cycle_end * 1000).toLocaleDateString()
    : '—'
);

// Últimos 7 dias, por origem: o que saiu, o que falhou e o que esperou a vez.
const statsRows = computed(() => {
  const byOrigin = state.value.stats?.by_origin || {};
  return ORIGINS.map(origin => {
    const row = byOrigin[origin] || {};
    return {
      origin,
      sent: row.sent || 0,
      failed:
        (row.failed || 0) + (row.uncertain || 0) + (row.disconnected || 0),
      waited: row.throttled || 0,
      fallback: row.fallback || 0,
    };
  });
});
const hasStats = computed(() =>
  statsRows.value.some(row => row.sent || row.failed || row.waited)
);

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

const resetQr = () => {
  qrValue.value = '';
  qrIndex.value = 0;
  qrDataUrl.value = '';
};

const renderQr = async value => {
  qrDataUrl.value = value
    ? await QRCode.toDataURL(value, { width: 240, margin: 1 }).catch(() => '')
    : '';
};

const apply = async data => {
  state.value = data;
  rateLimit.value = data.rate_limit_per_minute || 20;
  if (data.connected || isExpired.value || notConnected.value) {
    resetQr();
    if (data.connected) pairingCode.value = '';
    return;
  }
  // QR nulo com a sessão aguardando leitura é passageiro: mantém a contagem.
  if (data.qr && data.qr !== qrValue.value) {
    qrValue.value = data.qr;
    qrIndex.value += 1;
    qrShownAt.value = Date.now();
    await renderQr(data.qr);
  }
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
  run(async () => {
    resetQr();
    pairingCode.value = '';
    await WhatsappHybridAPI.reconnect(props.inbox.id);
    await load();
  }, 'ERRORS.CONNECT');

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

// Pareando: consulta a cada 3 s. Conectado: a cada 30 s, para a tela mostrar na hora
// se o celular desconectar (o servidor também revalida antes de cada envio).
onMounted(() => {
  load();
  timer = setInterval(() => {
    ticks += 1;
    if (pairing.value || (connected.value && ticks % 10 === 0)) load();
  }, 3000);
  clock = setInterval(() => {
    now.value = Date.now();
  }, 1000);
});

onBeforeUnmount(() => {
  if (timer) clearInterval(timer);
  if (clock) clearInterval(clock);
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
        v-else-if="isExpired"
        class="flex flex-col items-center gap-3 px-4 py-8 text-center border rounded-lg border-n-weak"
      >
        <span
          class="size-8 text-n-slate-10"
          :class="
            stoppedKey === 'DISCONNECTED'
              ? 'i-lucide-unplug'
              : 'i-lucide-timer-off'
          "
        />
        <p class="mb-0 text-base font-medium text-n-slate-12">
          {{ tw(`${stoppedKey}_TITLE`) }}
        </p>
        <p class="max-w-md mb-0 text-sm text-n-slate-11">
          {{ tk(`${stoppedKey}_HELP`) }}
        </p>
        <NextButton
          :is-loading="isBusy"
          icon="i-lucide-refresh-cw"
          :label="tw('RECONNECT')"
          @click="reconnect"
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
        <p
          v-if="timeLeft"
          class="mb-0 text-xs font-medium tabular-nums text-n-amber-11"
        >
          {{ tw('TIME_LEFT', { time: timeLeft }) }}
        </p>
        <p v-else class="mb-0 text-xs text-n-slate-11">
          {{ tw('PREPARING') }}
        </p>
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
        <p class="mb-0 text-xs text-n-slate-11">{{ tw('HINT') }}</p>
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
        <p class="w-full mb-0 text-xs text-n-slate-11">
          {{
            tk('CAMPAIGN_LIMIT', {
              limit: state.campaign_rate_limit_per_minute || 10,
            })
          }}
        </p>
      </div>
    </section>

    <section
      v-if="connected && !wrongNumber && cappingKey"
      class="flex items-start gap-2 px-4 py-3 text-sm rounded-xl"
      :class="
        cappingKey === 'BLOCKED'
          ? 'text-n-ruby-11 bg-n-ruby-3'
          : 'text-n-amber-11 bg-n-amber-3'
      "
    >
      <span class="i-lucide-gauge size-4 mt-0.5 shrink-0" />
      <span>
        {{
          tk(`CAPPING.${cappingKey}`, {
            used: capping.used ?? '—',
            total: capping.total ?? '—',
            end: cappingEnd,
          })
        }}
      </span>
    </section>

    <section
      v-if="connected && !wrongNumber"
      class="flex flex-col gap-3 p-5 border rounded-xl border-n-weak bg-n-solid-1"
    >
      <p class="mb-0 text-base font-medium text-n-slate-12">
        {{ tk('STATS.TITLE', { days: state.stats?.days || 7 }) }}
      </p>
      <p v-if="!hasStats" class="mb-0 text-sm text-n-slate-11">
        {{ tk('STATS.EMPTY') }}
      </p>
      <table v-else class="w-full text-sm">
        <thead>
          <tr class="text-left text-n-slate-11">
            <th class="py-1 font-normal">{{ tk('STATS.WHO') }}</th>
            <th class="py-1 font-normal text-right">{{ tk('STATS.SENT') }}</th>
            <th class="py-1 font-normal text-right">
              {{ tk('STATS.FAILED') }}
            </th>
            <th class="py-1 font-normal text-right">
              {{ tk('STATS.WAITED') }}
            </th>
            <th class="py-1 font-normal text-right">
              {{ tk('STATS.FALLBACK') }}
            </th>
          </tr>
        </thead>
        <tbody>
          <tr
            v-for="row in statsRows"
            :key="row.origin"
            class="border-t border-n-weak text-n-slate-12"
          >
            <td class="py-2">
              {{ tk(`ORIGINS.${row.origin.toUpperCase()}`) }}
            </td>
            <td class="py-2 text-right tabular-nums">{{ row.sent }}</td>
            <td class="py-2 text-right tabular-nums">{{ row.failed }}</td>
            <td class="py-2 text-right tabular-nums">{{ row.waited }}</td>
            <td class="py-2 text-right tabular-nums">{{ row.fallback }}</td>
          </tr>
        </tbody>
      </table>
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
