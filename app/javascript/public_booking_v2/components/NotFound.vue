<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useFlow } from '../composables/useBookingFlow';
import { safeAbsoluteUrl } from '../helpers/url';
import { WHATSAPP_HOME_URL } from '../helpers/whatsapp';
import MessageScreen from './MessageScreen.vue';
import WhatsAppButton from './WhatsAppButton.vue';

// Link inexistente, vencido ou cancelado (J1-A6, RA-17): recado simples, sem expor nenhum dado nem dizer se a página
// existe. Se já sabemos o WhatsApp da empresa (página carregada antes), ele vira a saída; senão, voltar ao WhatsApp
// para pedir um link novo a quem mandou.
const { page } = useFlow();
const { t } = useI18n();

const pageWhatsApp = computed(() =>
  safeAbsoluteUrl(page.value?.contact_whatsapp_url)
);
</script>

<template>
  <MessageScreen
    icon="i-lucide-link-2-off"
    :title="t('BOOKING_V2.NOT_FOUND.TITLE')"
    :body="t('BOOKING_V2.NOT_FOUND.BODY')"
  >
    <WhatsAppButton v-if="pageWhatsApp" :url="pageWhatsApp" variant="primary" />
    <WhatsAppButton
      v-else
      :url="WHATSAPP_HOME_URL"
      variant="primary"
      :label="t('BOOKING_V2.HELP.BACK_TO_WHATSAPP')"
    />
  </MessageScreen>
</template>
