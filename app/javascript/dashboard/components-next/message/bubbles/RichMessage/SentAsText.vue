<script setup>
// Envio rico que saiu como TEXTO (chat#1555): pelo WhatsApp Híbrido (WAHA), num canal sem o formato ou pela
// caixa API. O servidor grava `rich_message_sent_as: 'text'` e o texto enviado em `rich_message_sent_text`
// (corpo + versão em texto do tipo); a bolha mostra só esse texto, como o cliente recebeu, e uma linha discreta.
// Quem escolhe esta bolha é o registry.js, antes da bolha do tipo.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import BaseBubble from '../Base.vue';
import FormattedContent from '../Text/FormattedContent.vue';
import { useMessageContext } from '../../provider.js';

const { contentAttributes } = useMessageContext();
const { t } = useI18n();

const sentText = computed(() => {
  const text = contentAttributes.value?.richMessageSentText;
  return typeof text === 'string' ? text : '';
});
</script>

<template>
  <BaseBubble class="px-4 py-3" data-bubble-name="rich-sent-as-text">
    <div class="flex flex-col gap-1">
      <FormattedContent v-if="sentText" :content="sentText" />
      <span class="text-xs text-n-slate-11">
        {{ t('RICH_MESSAGE.SENT_AS_TEXT.LABEL') }}
      </span>
    </div>
  </BaseBubble>
</template>
