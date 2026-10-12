<script setup>
import { computed } from 'vue';

// #1149 — ícone do canal da caixa, num quadrado de cor neutra.
const props = defineProps({
  canal: { type: String, default: '' },
  grande: { type: Boolean, default: false },
});

const ICONES = {
  'Channel::Whatsapp': 'i-ri-whatsapp-line',
  'Channel::Instagram': 'i-ri-instagram-line',
  'Channel::FacebookPage': 'i-ri-messenger-line',
  'Channel::Email': 'i-lucide-mail',
  'Channel::WebWidget': 'i-lucide-globe',
  'Channel::Telegram': 'i-ri-telegram-line',
  'Channel::Sms': 'i-lucide-message-square',
  'Channel::TwilioSms': 'i-lucide-message-square',
  'Channel::Api': 'i-lucide-plug',
};

const icone = computed(() => ICONES[props.canal] || 'i-lucide-inbox');
</script>

<template>
  <span
    class="grid shrink-0 place-items-center rounded-xl bg-n-alpha-2 text-n-slate-12"
    :class="grande ? 'size-12' : 'size-10'"
    aria-hidden="true"
  >
    <span :class="[icone, grande ? 'size-6' : 'size-5']" />
  </span>
</template>
