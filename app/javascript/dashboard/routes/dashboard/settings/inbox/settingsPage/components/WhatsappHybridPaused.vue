<script setup>
import { useI18n } from 'vue-i18n';
import NextButton from 'dashboard/components-next/button/Button.vue';

// chat#1487 — WhatsApp API pausado: uma ação só, retomar.
defineProps({
  isBusy: { type: Boolean, default: false },
});

const emit = defineEmits(['resume']);

const { t } = useI18n();
</script>

<template>
  <div
    class="flex flex-col items-center gap-3 px-4 py-8 text-center border rounded-lg border-n-weak"
  >
    <span class="i-lucide-circle-pause size-8 text-n-slate-10" />
    <p class="mb-0 text-base font-medium text-n-slate-12">
      {{ t('INBOX_MGMT.WHATSAPP_HYBRID.PAUSE.PAUSED_TITLE') }}
    </p>
    <p class="max-w-md mb-0 text-sm text-n-slate-11">
      {{ t('INBOX_MGMT.WHATSAPP_HYBRID.PAUSE.PAUSED_HELP') }}
    </p>
    <NextButton
      :is-loading="isBusy"
      icon="i-lucide-play"
      :label="t('INBOX_MGMT.WHATSAPP_HYBRID.PAUSE.RESUME')"
      @click="emit('resume')"
    />
  </div>
</template>
