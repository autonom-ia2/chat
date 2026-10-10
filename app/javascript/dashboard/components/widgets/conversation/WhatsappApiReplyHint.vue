<script setup>
// chat#1067: fora da janela de 24h, com o WhatsApp Híbrido pronto, a resposta em texto livre
// sai pelo WhatsApp API. Aviso calmo, sem bloquear o envio; nunca em nota privada.
import { computed } from 'vue';

const props = defineProps({
  conversation: {
    type: Object,
    default: () => ({}),
  },
  isOnPrivateNote: {
    type: Boolean,
    default: false,
  },
});

const isVisible = computed(
  () =>
    props.conversation?.whatsapp_api_reply === true && !props.isOnPrivateNote
);
</script>

<template>
  <p
    v-show="isVisible"
    class="flex items-center gap-1.5 mx-2 mb-2 text-xs text-n-slate-11"
  >
    <span class="i-lucide-info size-3.5 flex-shrink-0" aria-hidden="true" />
    {{ $t('CONVERSATION.WHATSAPP_TRANSPORT.REPLY_HINT') }}
  </p>
</template>
