<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';

// chat#1477/#1487 — a conexão parou sem ser pausada: QR vencido, conexão encerrada ou aparelho desligado pelo
// WhatsApp. Uma ação só: gerar um QR novo.
const props = defineProps({
  // EXPIRED | DISCONNECTED | REMOVED (stoppedKeyFor)
  stoppedKey: { type: String, required: true },
  isBusy: { type: Boolean, default: false },
});

const emit = defineEmits(['reconnect']);

const { t } = useI18n();

// eslint-disable-next-line @intlify/vue-i18n/no-dynamic-keys
const tHybrid = key => t(`INBOX_MGMT.WHATSAPP_HYBRID.${key}`);
// Mesmos títulos de QR vencido/desconectado da caixa WhatsApp API.
// eslint-disable-next-line @intlify/vue-i18n/no-dynamic-keys
const tWaha = key => t(`INBOX_MGMT.WAHA_CONNECTION.${key}`);

const title = computed(() =>
  props.stoppedKey === 'REMOVED'
    ? tHybrid('REMOVED_TITLE')
    : tWaha(`${props.stoppedKey}_TITLE`)
);
const help = computed(() => tHybrid(`${props.stoppedKey}_HELP`));
const icon = computed(() =>
  props.stoppedKey === 'EXPIRED' ? 'i-lucide-timer-off' : 'i-lucide-unplug'
);
</script>

<template>
  <div class="flex flex-col items-start gap-3">
    <span class="size-8 text-n-slate-10" :class="icon" aria-hidden="true" />
    <h2 class="m-0 text-lg font-semibold text-n-slate-12">{{ title }}</h2>
    <p class="mb-0 text-base leading-relaxed text-n-slate-12">{{ help }}</p>
    <Button
      data-reconnect
      :is-loading="isBusy"
      icon="i-lucide-refresh-cw"
      size="lg"
      class="w-full mt-1 !min-h-12 !rounded-xl sm:w-auto"
      :label="$t('INBOX_MGMT.WAHA_CONNECTION.RECONNECT')"
      @click="emit('reconnect')"
    />
  </div>
</template>
