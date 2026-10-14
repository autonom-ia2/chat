<script setup>
import { computed, nextTick, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useFlow } from '../composables/useBookingFlow';
import { safeAbsoluteUrl } from '../helpers/url';
import { WHATSAPP_HOME_URL } from '../helpers/whatsapp';
import BrandHeader from './BrandHeader.vue';
import ContactRequestForm from './ContactRequestForm.vue';
import MessageScreen from './MessageScreen.vue';
import WhatsAppButton from './WhatsAppButton.vue';

// Página pausada (RA-17, #1401): diz que está fechada e sempre dá uma saída, uma por vez. Com o WhatsApp da empresa,
// ele. Sem ele, o pedido de contato (o servidor só manda o formulário quando o responsável ainda atende). Sem nenhum
// dos dois, voltar ao WhatsApp para falar com quem mandou o link.
const { page, isContactRequested } = useFlow();
const { t } = useI18n();

const hasWhatsApp = computed(
  () => !!safeAbsoluteUrl(page.value.contact_whatsapp_url)
);
const canRequestContact = computed(
  () => !hasWhatsApp.value && !!page.value.form_token
);
const body = computed(() => {
  if (hasWhatsApp.value) return t('BOOKING_V2.PAUSED.BODY');
  if (canRequestContact.value) return t('BOOKING_V2.PAUSED.BODY_CONTACT');
  return t('BOOKING_V2.PAUSED.BODY_NO_WHATSAPP');
});

watch(isContactRequested, isDone => {
  if (!isDone) return;
  nextTick(() => document.querySelector('[data-step-heading]')?.focus());
});
</script>

<template>
  <div class="flex flex-col gap-6">
    <BrandHeader :page="page" />
    <MessageScreen
      v-if="isContactRequested"
      icon="i-lucide-circle-check"
      :title="t('BOOKING_V2.NO_SLOT.DONE_TITLE')"
      :body="t('BOOKING_V2.NO_SLOT.DONE_BODY')"
    />
    <MessageScreen
      v-else
      icon="i-lucide-calendar-off"
      :title="t('BOOKING_V2.PAUSED.TITLE')"
      :body="body"
    >
      <WhatsAppButton
        v-if="hasWhatsApp"
        :url="page.contact_whatsapp_url"
        variant="primary"
        :label="t('BOOKING_V2.PAUSED.WHATSAPP')"
      />
      <div v-else-if="canRequestContact" class="text-start">
        <ContactRequestForm />
      </div>
      <WhatsAppButton
        v-else
        :url="WHATSAPP_HOME_URL"
        variant="primary"
        :label="t('BOOKING_V2.HELP.BACK_TO_WHATSAPP')"
      />
    </MessageScreen>
  </div>
</template>
