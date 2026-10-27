<script setup>
import { computed } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';
import { tipoDoIconeDaCaixa } from 'dashboard/helper/inbox';

// #1149 — ícone do canal da caixa, num quadrado de cor neutra.
// #2255 — com o id da caixa, o ícone sai da caixa inteira (store): o WhatsApp do celular
// é uma caixa API e leva o ícone do WhatsApp.
const props = defineProps({
  canal: { type: String, default: '' },
  caixaId: { type: [Number, String], default: null },
  grande: { type: Boolean, default: false },
});

const caixaPorId = useMapGetter('inboxes/getInboxById');

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

const tipo = computed(() => {
  const caixa = props.caixaId ? caixaPorId.value(props.caixaId) : null;
  return tipoDoIconeDaCaixa(caixa) || props.canal;
});

const icone = computed(() => ICONES[tipo.value] || 'i-lucide-inbox');
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
