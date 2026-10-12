<script setup>
import { defineAsyncComponent } from 'vue';
import { useI18n } from 'vue-i18n';

// hCaptcha só aparece quando a página manda `captcha_site_key`. O pacote é carregado sob demanda: quem não
// precisa de captcha não baixa nada (RA-16).
defineProps({
  siteKey: { type: String, required: true },
});
const emit = defineEmits(['verify', 'expire']);

const VueHcaptcha = defineAsyncComponent(
  () => import('@hcaptcha/vue3-hcaptcha')
);
const { t, locale } = useI18n();
const language = String(locale.value).split('_')[0];
// O quadro do hCaptcha vem de fora e não enxerga as cores da página: recebe o tema do aparelho ao ser montado (#1295).
const theme = window.matchMedia?.('(prefers-color-scheme: dark)').matches
  ? 'dark'
  : 'light';
</script>

<template>
  <div class="flex flex-col items-center gap-1">
    <p class="sr-only">{{ t('BOOKING_V2.DETAILS.CAPTCHA') }}</p>
    <VueHcaptcha
      :sitekey="siteKey"
      :language="language"
      :theme="theme"
      @verify="token => emit('verify', token)"
      @expired="emit('expire')"
      @challenge-expired="emit('expire')"
      @error="emit('expire')"
    />
  </div>
</template>
