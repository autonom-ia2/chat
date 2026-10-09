<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useFlow } from '../composables/useBookingFlow';
import BrandHeader from './BrandHeader.vue';
import MessageScreen from './MessageScreen.vue';
import WhatsAppButton from './WhatsAppButton.vue';

// Link do cliente já usado: mostra o que sabemos e o WhatsApp. Remarcar e cancelar pelo link chegam na F2-A.
const { page } = useFlow();
const { t } = useI18n();

const agentName = computed(() => page.value.agent_name || '');
const body = computed(() =>
  agentName.value
    ? t('BOOKING_V2.ALREADY.BODY', { name: agentName.value })
    : t('BOOKING_V2.ALREADY.BODY_NO_NAME')
);
</script>

<template>
  <div class="flex flex-col gap-6">
    <BrandHeader :page="page" />
    <MessageScreen
      icon="i-lucide-calendar-check"
      :title="t('BOOKING_V2.ALREADY.TITLE')"
      :body="body"
    >
      <p v-if="page.contact_whatsapp_url" class="text-base text-slate-700">
        {{ t('BOOKING_V2.ALREADY.CHANGE') }}
      </p>
      <WhatsAppButton
        :url="page.contact_whatsapp_url"
        variant="primary"
        :label="t('BOOKING_V2.ALREADY.WHATSAPP')"
      />
    </MessageScreen>
  </div>
</template>
