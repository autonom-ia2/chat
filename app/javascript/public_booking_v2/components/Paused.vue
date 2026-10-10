<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useFlow } from '../composables/useBookingFlow';
import { safeAbsoluteUrl } from '../helpers/url';
import BrandHeader from './BrandHeader.vue';
import MessageScreen from './MessageScreen.vue';
import WhatsAppButton from './WhatsAppButton.vue';

// Página pausada (RA-17): diz que está fechada e oferece o WhatsApp da empresa quando existe.
const { page } = useFlow();
const { t } = useI18n();

const hasWhatsApp = computed(
  () => !!safeAbsoluteUrl(page.value.contact_whatsapp_url)
);
</script>

<template>
  <div class="flex flex-col gap-6">
    <BrandHeader :page="page" />
    <MessageScreen
      icon="i-lucide-calendar-off"
      :title="t('BOOKING_V2.PAUSED.TITLE')"
      :body="
        hasWhatsApp
          ? t('BOOKING_V2.PAUSED.BODY')
          : t('BOOKING_V2.PAUSED.BODY_NO_WHATSAPP')
      "
    >
      <WhatsAppButton
        :url="page.contact_whatsapp_url"
        variant="primary"
        :label="t('BOOKING_V2.PAUSED.WHATSAPP')"
      />
    </MessageScreen>
  </div>
</template>
