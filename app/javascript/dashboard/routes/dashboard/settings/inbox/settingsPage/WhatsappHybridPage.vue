<script setup>
import { ref, computed, onMounted, onBeforeUnmount } from 'vue';
import { useI18n } from 'vue-i18n';
import QRCode from 'qrcode';
import { useAlert } from 'dashboard/composables';
import WhatsappHybridAPI from 'dashboard/api/whatsappHybrid';
import Button from 'dashboard/components-next/button/Button.vue';
import { qrSecondsLeft, formatSeconds } from 'dashboard/helper/wahaQrWindow';
import {
  stoppedKeyFor,
  statusKeyFor,
  phaseFor,
  phoneLabel,
  PHASE_TONES,
} from './whatsappHybridState';
import WhatsappHybridHeroi from './components/WhatsappHybridHeroi.vue';
import WhatsappHybridConnect from './components/WhatsappHybridConnect.vue';
import WhatsappHybridPairing from './components/WhatsappHybridPairing.vue';
import WhatsappHybridStopped from './components/WhatsappHybridStopped.vue';
import WhatsappHybridPaused from './components/WhatsappHybridPaused.vue';
import WhatsappHybridNotices from './components/WhatsappHybridNotices.vue';
import WhatsappHybridLimits from './components/WhatsappHybridLimits.vue';
import WhatsappHybridRisk from './components/WhatsappHybridRisk.vue';
import WhatsappHybridRouting from './components/WhatsappHybridRouting.vue';
import WhatsappHybridStats from './components/WhatsappHybridStats.vue';
import WhatsappHybridPause from './components/WhatsappHybridPause.vue';
import WhatsappHybridDisconnect from './components/WhatsappHybridDisconnect.vue';

// Aba "WhatsApp API" da caixa WhatsApp Oficial (chat#1067): a mesma caixa ganha um segundo
// caminho de envio, usado depois de 24 horas da última mensagem do cliente.
// chat#1487 — no padrão das telas novas: herói escuro com o selo do estado, uma caixa de situação com uma ação
// principal por estado, cartões arredondados e as ações raras (pausar, desconectar) no fim, com confirmação.
const props = defineProps({
  inbox: { type: Object, required: true },
});

const { t } = useI18n();
// eslint-disable-next-line @intlify/vue-i18n/no-dynamic-keys
const tk = key => t(`INBOX_MGMT.WHATSAPP_HYBRID.${key}`);

const QR_POLL_MS = 3000;
const CONNECTED_POLL_TICKS = 10;

const state = ref({ status: 'loading' });
const qrDataUrl = ref('');
const pairingCode = ref('');
const isBusy = ref(false);
// Posição do QR atual na rodada de pareamento (1..6) e quando ele apareceu.
const qrValue = ref('');
const qrIndex = ref(0);
const qrShownAt = ref(0);
const now = ref(Date.now());
let timer = null;
let clock = null;
let ticks = 0;

const phase = computed(() => phaseFor(state.value));
const connected = computed(() => phase.value === 'connected');
const paused = computed(() => phase.value === 'paused');
const stoppedKey = computed(() => stoppedKeyFor(state.value));
const statusKey = computed(() => statusKeyFor(state.value));
const statusLabel = computed(() =>
  ['loading', 'unavailable'].includes(phase.value)
    ? ''
    : tk(`STATUS.${statusKey.value}`)
);
const phaseTone = computed(
  () => PHASE_TONES[phase.value] || 'bg-n-solid-1 ring-n-weak'
);
const hasConnection = computed(
  () => !['loading', 'unavailable', 'not_connected'].includes(phase.value)
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

const renderQr = async value => {
  qrDataUrl.value = value
    ? await QRCode.toDataURL(value, { width: 240, margin: 1 }).catch(() => '')
    : '';
};

const apply = async data => {
  state.value = data;
  if (phaseFor(data) !== 'pairing') {
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

const retry = () => {
  state.value = { status: 'loading' };
  load();
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

const pause = () =>
  run(() => WhatsappHybridAPI.pause(props.inbox.id), 'ERRORS.PAUSE');

// Retomar religa sem QR; se o WhatsApp tiver desvinculado o aparelho, a resposta já traz o QR.
const resume = () =>
  run(() => WhatsappHybridAPI.resume(props.inbox.id), 'ERRORS.RESUME');

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
    const connectedPoll =
      state.value.connected && ticks % CONNECTED_POLL_TICKS === 0;
    if (phase.value === 'pairing' || connectedPoll) load();
  }, QR_POLL_MS);
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
  <div class="flex flex-col w-full max-w-3xl gap-5 py-6">
    <WhatsappHybridHeroi :status-key="statusKey" :status-label="statusLabel" />

    <div
      v-if="phase === 'loading'"
      data-hybrid-loading
      aria-busy="true"
      class="h-48 rounded-2xl bg-n-alpha-2 animate-pulse"
    >
      <span class="sr-only">{{ tk('LOADING') }}</span>
    </div>

    <section
      v-else-if="phase === 'unavailable'"
      data-hybrid-error
      role="alert"
      class="flex flex-col items-start gap-3 p-5 sm:p-6 rounded-2xl ring-1 ring-inset ring-n-weak bg-n-solid-1"
    >
      <p class="mb-0 text-base text-n-slate-12">{{ tk('LOAD_ERROR') }}</p>
      <Button
        icon="i-lucide-refresh-cw"
        color="slate"
        variant="outline"
        class="min-h-11"
        :label="tk('RETRY')"
        @click="retry"
      />
    </section>

    <template v-else>
      <section
        data-situacao
        :data-phase="phase"
        aria-live="polite"
        class="p-5 sm:p-6 rounded-2xl ring-1 ring-inset"
        :class="phaseTone"
      >
        <WhatsappHybridConnect
          v-if="phase === 'not_connected'"
          :is-busy="isBusy"
          @connect="connect"
        />
        <WhatsappHybridPaused
          v-else-if="paused"
          :is-busy="isBusy"
          @resume="resume"
        />
        <WhatsappHybridStopped
          v-else-if="phase === 'stopped'"
          :stopped-key="stoppedKey"
          :is-busy="isBusy"
          @reconnect="reconnect"
        />
        <WhatsappHybridPairing
          v-else-if="phase === 'pairing'"
          :qr-data-url="qrDataUrl"
          :time-left="timeLeft"
          :pairing-code="pairingCode"
          :is-busy="isBusy"
          @request-code="requestCode"
          @new-qr="reconnect"
        />
        <div v-else class="flex flex-col items-start gap-2">
          <span
            class="size-8"
            :class="
              connected
                ? 'i-lucide-circle-check text-n-teal-10'
                : 'i-lucide-circle-alert text-n-ruby-10'
            "
            aria-hidden="true"
          />
          <h2 class="m-0 text-lg font-semibold text-n-slate-12">
            {{
              connected
                ? tk('STATE.CONNECTED_TITLE')
                : tk('STATE.WRONG_NUMBER_TITLE')
            }}
          </h2>
          <p class="mb-0 text-base leading-relaxed text-n-slate-12">
            {{
              connected
                ? t('INBOX_MGMT.WHATSAPP_HYBRID.CONNECTED_HELP', {
                    phone: phoneLabel(state.phone),
                  })
                : t('INBOX_MGMT.WHATSAPP_HYBRID.WRONG_NUMBER', {
                    phone: phoneLabel(state.phone),
                  })
            }}
          </p>
        </div>
      </section>

      <WhatsappHybridNotices
        :same-number-inboxes="state.same_number_inboxes || []"
        :show-app-reminder="connected || paused"
      />

      <template v-if="connected">
        <WhatsappHybridLimits :state="state" :now="now" />
        <WhatsappHybridRisk
          :accepted="Boolean(state.risk_accepted)"
          :is-busy="isBusy"
          @change="value => save({ risk_accepted: value })"
        />
        <WhatsappHybridRouting
          v-if="state.risk_accepted"
          :state="state"
          @save="save"
        />
        <WhatsappHybridStats :stats="state.stats" />
      </template>

      <section
        v-if="hasConnection"
        data-hybrid-more
        class="flex flex-col gap-3 pt-5 border-t border-n-weak"
      >
        <h2 class="m-0 text-base font-semibold text-n-slate-12">
          {{ tk('MORE.TITLE') }}
        </h2>
        <div class="flex flex-col gap-2 sm:flex-row sm:flex-wrap">
          <WhatsappHybridPause
            v-if="connected"
            :is-busy="isBusy"
            @confirm="pause"
          />
          <WhatsappHybridDisconnect :is-busy="isBusy" @confirm="disconnect" />
        </div>
      </section>
    </template>
  </div>
</template>
