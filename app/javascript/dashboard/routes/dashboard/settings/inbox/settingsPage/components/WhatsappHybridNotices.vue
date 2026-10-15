<script setup>
import { useI18n } from 'vue-i18n';

// chat#1487 — avisos de saúde do número na aba WhatsApp API. Só avisam: nada é bloqueado.
// O motor não informa quando o app foi aberto no celular, então o lembrete dos 14 dias é fixo.
defineProps({
  sameNumberInboxes: { type: Array, default: () => [] },
  showAppReminder: { type: Boolean, default: false },
});

const { t } = useI18n();
</script>

<template>
  <section
    v-for="name in sameNumberInboxes"
    :key="name"
    data-test="same-number"
    class="flex items-start gap-2 px-4 py-3 text-sm rounded-xl text-n-amber-11 bg-n-amber-3"
  >
    <span class="i-lucide-triangle-alert size-4 mt-0.5 shrink-0" />
    <span>
      {{ t('INBOX_MGMT.WHATSAPP_HYBRID.NOTICES.SAME_NUMBER', { inbox: name }) }}
    </span>
  </section>
  <p
    v-if="showAppReminder"
    data-test="app-reminder"
    class="flex items-start gap-2 px-1 mb-0 text-xs text-n-slate-11"
  >
    <span class="i-lucide-smartphone size-4 shrink-0" />
    <span>{{ t('INBOX_MGMT.WHATSAPP_HYBRID.NOTICES.APP_EVERY_14_DAYS') }}</span>
  </p>
</template>
