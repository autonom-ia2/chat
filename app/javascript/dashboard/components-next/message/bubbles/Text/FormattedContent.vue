<script setup>
import { computed } from 'vue';
import { useMessageContext } from '../../provider.js';

import MessageFormatter from 'shared/helpers/MessageFormatter.js';
import { MESSAGE_VARIANTS } from '../../constants';
import { formatarWhatsapp } from 'dashboard/components-next/conversa-canal/formatacaoWhatsapp';
import { useFormatoDoWhatsapp } from 'dashboard/components-next/conversa-canal/useFormatoDoWhatsapp';

const props = defineProps({
  content: {
    type: String,
    required: true,
  },
});

const { variant } = useMessageContext();
// Pele do WhatsApp (#1732): texto escrito no app sai com a formatação do app.
const formatoDoWhatsapp = useFormatoDoWhatsapp();

const formattedContent = computed(() => {
  if (variant.value === MESSAGE_VARIANTS.ACTIVITY) {
    return props.content;
  }

  if (formatoDoWhatsapp.value) return formatarWhatsapp(props.content);

  return new MessageFormatter(props.content).formattedMessage;
});
</script>

<template>
  <span v-dompurify-html="formattedContent" class="prose prose-bubble" />
</template>
