<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useFlow } from '../composables/useBookingFlow';
import ActionButton from './ActionButton.vue';
import CaptchaField from './CaptchaField.vue';
import HoneypotField from './HoneypotField.vue';
import WhatsAppButton from './WhatsAppButton.vue';

// Fim de todo formulário: aviso das mensagens (só com `notices_enabled`, RA-18/J2-A9), honeypot, hCaptcha (só com
// chave), erro geral com saída pelo WhatsApp (RA-17) e o botão principal.
defineProps({
  submitLabel: { type: String, required: true },
});

const { page, form, formError, captchaToken, captchaKey, isSubmitting } =
  useFlow();
const { t } = useI18n();

const siteKey = computed(() => page.value?.captcha_site_key || '');
const showWhatsApp = computed(
  () => !!formError.value && formError.value !== 'BOOKING_V2.ERRORS.CAPTCHA'
);
const onVerify = token => {
  captchaToken.value = token;
};
const onExpire = () => {
  captchaToken.value = '';
};
</script>

<template>
  <div class="flex flex-col gap-4">
    <p
      v-if="page.notices_enabled"
      data-testid="notices-consent"
      class="text-base text-slate-700"
    >
      {{ t('BOOKING_V2.DETAILS.NOTICE') }}
    </p>
    <HoneypotField v-model="form.company" />
    <CaptchaField
      v-if="siteKey"
      :key="captchaKey"
      :site-key="siteKey"
      @verify="onVerify"
      @expire="onExpire"
    />
    <div v-if="formError" class="flex flex-col gap-3">
      <p
        role="alert"
        class="rounded-xl bg-red-50 p-4 text-base font-medium text-red-800"
      >
        {{ t(formError) }}
      </p>
      <WhatsAppButton v-if="showWhatsApp" :url="page.contact_whatsapp_url" />
    </div>
    <ActionButton type="submit" :disabled="isSubmitting">
      {{ isSubmitting ? t('BOOKING_V2.DETAILS.SENDING') : submitLabel }}
    </ActionButton>
  </div>
</template>
