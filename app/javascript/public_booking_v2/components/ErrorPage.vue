<script setup>
import { useI18n } from 'vue-i18n';
import { useFlow } from '../composables/useBookingFlow';
import ActionButton from './ActionButton.vue';
import MessageScreen from './MessageScreen.vue';
import WhatsAppButton from './WhatsAppButton.vue';

// Falha ao abrir (rede, servidor, fuso inválido): sempre "Tentar de novo" e, se houver, o WhatsApp (RA-17).
const { page, load } = useFlow();
const { t } = useI18n();
</script>

<template>
  <MessageScreen
    icon="i-lucide-cloud-off"
    :title="t('BOOKING_V2.ERROR_PAGE.TITLE')"
    :body="t('BOOKING_V2.ERROR_PAGE.BODY')"
  >
    <ActionButton @click="load">
      {{ t('BOOKING_V2.ERROR_PAGE.RETRY') }}
    </ActionButton>
    <WhatsAppButton :url="page?.contact_whatsapp_url || ''" />
  </MessageScreen>
</template>
