<script setup>
import { useI18n } from 'vue-i18n';
import { useFlow } from '../composables/useBookingFlow';
import MessageScreen from './MessageScreen.vue';
import WhatsAppButton from './WhatsAppButton.vue';

// Link inexistente, vencido ou cancelado (J1-A6): recado simples, sem expor nenhum dado. Se já sabemos o WhatsApp
// da empresa (página carregada antes), ele vira a saída; senão, nada.
const { page } = useFlow();
const { t } = useI18n();
</script>

<template>
  <MessageScreen
    icon="i-lucide-link-2-off"
    :title="t('BOOKING_V2.NOT_FOUND.TITLE')"
    :body="t('BOOKING_V2.NOT_FOUND.BODY')"
  >
    <WhatsAppButton :url="page?.contact_whatsapp_url || ''" variant="primary" />
  </MessageScreen>
</template>
