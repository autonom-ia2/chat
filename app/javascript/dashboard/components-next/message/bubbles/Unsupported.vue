<script setup>
import { computed } from 'vue';
import { useMessageContext } from '../provider.js';
import { useInbox } from 'dashboard/composables/useInbox';
import { hybridRecoveryNoteKey } from '../helpers/hybridRecovery.js';
import BaseBubble from './Base.vue';

const { inboxId, contentAttributes } = useMessageContext();

const {
  isAFacebookInbox,
  isAnInstagramChannel,
  isATiktokChannel,
  isAWhatsAppChannel,
} = useInbox(inboxId.value);

// chat#1489: enquanto o WhatsApp API busca o conteúdo no celular, ou quando não conseguiu.
const recoveryKey = computed(() =>
  hybridRecoveryNoteKey(contentAttributes?.value)
);

const unsupportedMessageKey = computed(() => {
  if (recoveryKey.value) return recoveryKey.value;
  if (isAFacebookInbox.value)
    return 'CONVERSATION.UNSUPPORTED_MESSAGE_FACEBOOK';
  if (isAnInstagramChannel.value)
    return 'CONVERSATION.UNSUPPORTED_MESSAGE_INSTAGRAM';
  if (isATiktokChannel.value) return 'CONVERSATION.UNSUPPORTED_MESSAGE_TIKTOK';
  if (isAWhatsAppChannel.value)
    return 'CONVERSATION.UNSUPPORTED_MESSAGE_WHATSAPP';
  return 'CONVERSATION.UNSUPPORTED_MESSAGE';
});

const isPending = computed(
  () => contentAttributes?.value?.hybridRecovery === 'pending'
);
</script>

<template>
  <BaseBubble
    class="px-4 py-3 text-sm"
    :class="{ 'text-n-slate-11': isPending }"
    data-bubble-name="unsupported"
  >
    {{ $t(unsupportedMessageKey) }}
  </BaseBubble>
</template>
