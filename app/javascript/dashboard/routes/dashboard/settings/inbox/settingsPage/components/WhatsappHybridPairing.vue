<script setup>
import Button from 'dashboard/components-next/button/Button.vue';

// chat#1487 — o QR Code para ler com o celular. Ler é a ação principal; código e QR novo ficam como alternativas.
defineProps({
  qrDataUrl: { type: String, default: '' },
  timeLeft: { type: String, default: '' },
  pairingCode: { type: String, default: '' },
  isBusy: { type: Boolean, default: false },
});

const emit = defineEmits(['requestCode', 'newQr']);

const STEPS = ['STEP_1', 'STEP_2', 'STEP_3'];
</script>

<template>
  <div class="flex flex-col items-center gap-4 text-center">
    <h2 class="m-0 text-lg font-semibold text-n-slate-12">
      {{ $t('INBOX_MGMT.WHATSAPP_HYBRID.SCAN_TITLE') }}
    </h2>
    <div
      class="flex items-center justify-center p-2 bg-white rounded-xl size-[240px] max-w-full ring-1 ring-n-weak"
    >
      <img
        v-if="qrDataUrl"
        :src="qrDataUrl"
        :alt="$t('INBOX_MGMT.WHATSAPP_HYBRID.QR_ALT')"
        class="size-full"
      />
      <span
        v-else
        class="i-lucide-loader-circle animate-spin size-6 text-n-slate-10"
        aria-hidden="true"
      />
    </div>
    <p
      v-if="timeLeft"
      role="status"
      class="mb-0 text-sm font-medium tabular-nums text-n-amber-11"
    >
      {{ $t('INBOX_MGMT.WAHA_CONNECTION.TIME_LEFT', { time: timeLeft }) }}
    </p>
    <p v-else class="mb-0 text-sm text-n-slate-11">
      {{ $t('INBOX_MGMT.WAHA_CONNECTION.PREPARING') }}
    </p>
    <ol
      class="flex flex-col w-full max-w-md gap-2 p-0 m-0 text-sm text-left list-none text-n-slate-12"
    >
      <li v-for="(step, index) in STEPS" :key="step" class="flex gap-3">
        <span
          class="grid text-xs font-semibold rounded-full size-6 shrink-0 place-items-center bg-n-blue-3 text-n-blue-11"
          aria-hidden="true"
        >
          {{ index + 1 }}
        </span>
        <!-- eslint-disable-next-line @intlify/vue-i18n/no-dynamic-keys -->
        <span>{{ $t(`INBOX_MGMT.WHATSAPP_HYBRID.${step}`) }}</span>
      </li>
    </ol>
    <div v-if="pairingCode" class="flex flex-col items-center gap-1">
      <p
        data-pairing-code
        class="mb-0 font-mono text-2xl font-semibold tracking-widest text-n-slate-12"
      >
        {{ pairingCode }}
      </p>
      <p class="mb-0 text-sm text-n-slate-11">
        {{ $t('INBOX_MGMT.WHATSAPP_HYBRID.CODE_HELP') }}
      </p>
    </div>
    <div class="flex flex-col w-full gap-2 sm:flex-row sm:justify-center">
      <Button
        v-if="!pairingCode"
        data-use-code
        :is-loading="isBusy"
        color="slate"
        variant="outline"
        icon="i-lucide-keyboard"
        class="min-h-11"
        :label="$t('INBOX_MGMT.WHATSAPP_HYBRID.USE_CODE')"
        @click="emit('requestCode')"
      />
      <Button
        :is-loading="isBusy"
        color="slate"
        variant="outline"
        icon="i-lucide-refresh-cw"
        class="min-h-11"
        :label="$t('INBOX_MGMT.WHATSAPP_HYBRID.NEW_QR')"
        @click="emit('newQr')"
      />
    </div>
    <p class="mb-0 text-xs text-n-slate-11">
      {{ $t('INBOX_MGMT.WAHA_CONNECTION.HINT') }}
    </p>
  </div>
</template>
