<script setup>
import { ref, computed, onMounted, onBeforeUnmount } from 'vue';
import { useI18n } from 'vue-i18n';
import QRCode from 'qrcode';
import WahaInboxAPI from 'dashboard/api/wahaInbox';
import NextButton from 'dashboard/components-next/button/Button.vue';
import { qrSecondsLeft, formatSeconds } from 'dashboard/helper/wahaQrWindow';

const props = defineProps({
  inbox: { type: Object, required: true },
});

const { t } = useI18n();
// eslint-disable-next-line @intlify/vue-i18n/no-dynamic-keys
const tk = (key, params) => t(`INBOX_MGMT.WAHA_CONNECTION.${key}`, params);

const status = ref('unknown');
const phone = ref('');
const qrDataUrl = ref('');
const isReconnecting = ref(false);
// Posição do QR atual na rodada de pareamento (1..6) e quando ele apareceu.
const qrValue = ref('');
const qrIndex = ref(0);
const qrShownAt = ref(0);
const now = ref(Date.now());
let timer = null;
let clock = null;

const connected = computed(() => status.value === 'connected');
// FAILED (rodada de QR esgotada) e STOPPED (sessão desligada): não chega QR
// novo sem reiniciar a sessão. O texto muda conforme o motivo.
const isExpired = computed(() =>
  ['failed', 'disconnected'].includes(status.value)
);
const stoppedKey = computed(() =>
  status.value === 'disconnected' ? 'DISCONNECTED' : 'EXPIRED'
);
const timeLeft = computed(() => {
  if (!qrIndex.value || !qrDataUrl.value) return '';
  const elapsed = Math.max(now.value - qrShownAt.value, 0) / 1000;
  return formatSeconds(qrSecondsLeft(qrIndex.value, elapsed));
});

const resetQr = () => {
  qrValue.value = '';
  qrIndex.value = 0;
  qrDataUrl.value = '';
};

const STATUS_META = {
  connected: { key: 'CONNECTED', tone: 'text-n-teal-11 bg-n-teal-3' },
  awaiting_scan: { key: 'AWAITING', tone: 'text-n-amber-11 bg-n-amber-3' },
  connecting: { key: 'CONNECTING', tone: 'text-n-amber-11 bg-n-amber-3' },
  failed: { key: 'FAILED', tone: 'text-n-ruby-11 bg-n-ruby-3' },
  disconnected: { key: 'DISCONNECTED', tone: 'text-n-slate-11 bg-n-alpha-2' },
  unknown: { key: 'CHECKING', tone: 'text-n-slate-11 bg-n-alpha-2' },
};
const statusMeta = computed(
  () => STATUS_META[status.value] || STATUS_META.unknown
);

const renderQr = async value => {
  if (!value) {
    qrDataUrl.value = '';
    return;
  }
  try {
    qrDataUrl.value = await QRCode.toDataURL(value, { width: 240, margin: 1 });
  } catch {
    qrDataUrl.value = '';
  }
};

// Só a resposta da consulta mais recente vale: uma consulta disparada antes do
// "Gerar novo QR Code" não pode trazer de volta o estado antigo.
let latestRequest = 0;

const poll = async () => {
  latestRequest += 1;
  const request = latestRequest;
  try {
    const { data } = await WahaInboxAPI.connection(props.inbox.id);
    if (request !== latestRequest) return;
    status.value = data.status;
    phone.value = data.phone;
    // QR nulo com a sessão aguardando leitura é passageiro: mantém a contagem.
    if (data.connected || isExpired.value) {
      resetQr();
    } else if (data.qr && data.qr !== qrValue.value) {
      qrValue.value = data.qr;
      qrIndex.value += 1;
      qrShownAt.value = Date.now();
      await renderQr(data.qr);
    }
  } catch {
    if (request === latestRequest) status.value = 'unknown';
  }
};

const reconnect = async () => {
  isReconnecting.value = true;
  latestRequest += 1;
  try {
    await WahaInboxAPI.reconnect(props.inbox.id);
    status.value = 'connecting';
    resetQr();
    await poll();
  } finally {
    isReconnecting.value = false;
  }
};

onMounted(() => {
  poll();
  timer = setInterval(poll, 3000);
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
  <div class="py-6">
    <div
      class="flex flex-col gap-4 p-5 border rounded-xl border-n-weak bg-n-solid-1"
    >
      <div class="flex items-center justify-between gap-3">
        <div class="flex items-center gap-3 min-w-0">
          <span
            class="flex items-center justify-center rounded-full size-10 bg-n-alpha-2"
          >
            <span class="i-lucide-message-circle size-5 text-n-slate-11" />
          </span>
          <div class="min-w-0">
            <p class="mb-1 text-sm font-medium text-n-slate-12 truncate">
              {{ phone || inbox.name }}
              <span
                class="inline-flex items-center gap-1 px-2 py-0.5 ml-1 text-xs font-medium rounded-md"
                :class="statusMeta.tone"
              >
                <span class="rounded-full size-1.5 bg-current" />
                {{ tk(`STATUS.${statusMeta.key}`) }}
              </span>
            </p>
            <p class="mb-0 text-xs text-n-slate-11">{{ tk('SUBTITLE') }}</p>
          </div>
        </div>
        <NextButton
          v-if="!connected && !isExpired"
          :is-loading="isReconnecting"
          icon="i-lucide-refresh-cw"
          color="slate"
          variant="outline"
          size="sm"
          :label="tk('RECONNECT')"
          @click="reconnect"
        />
      </div>

      <div
        v-if="connected"
        class="flex items-center gap-2 px-4 py-3 text-sm rounded-lg text-n-teal-11 bg-n-teal-3"
      >
        <span class="i-lucide-circle-check size-4" />
        {{ tk('CONNECTED_HELP') }}
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
          {{ tk(`${stoppedKey}_TITLE`) }}
        </p>
        <p class="max-w-md mb-0 text-sm text-n-slate-11">
          {{ tk(`${stoppedKey}_HELP`) }}
        </p>
        <NextButton
          :is-loading="isReconnecting"
          icon="i-lucide-refresh-cw"
          :label="tk('RECONNECT')"
          @click="reconnect"
        />
      </div>

      <div
        v-else
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
            alt="QR Code"
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
          {{ tk('TIME_LEFT', { time: timeLeft }) }}
        </p>
        <p v-else class="mb-0 text-xs text-n-slate-11">
          {{ tk('PREPARING') }}
        </p>
        <ol
          class="mb-0 text-xs leading-5 text-left text-n-slate-11 list-decimal list-inside"
        >
          <li>{{ tk('STEP_1') }}</li>
          <li>{{ tk('STEP_2') }}</li>
          <li>{{ tk('STEP_3') }}</li>
        </ol>
        <p class="mb-0 text-xs text-n-slate-11">{{ tk('HINT') }}</p>
      </div>
    </div>
  </div>
</template>
