<script setup>
// Mensagem apagada pela equipe (#1702), como no WhatsApp: o círculo cortado e o aviso
// em cinza e itálico — "Você apagou esta mensagem" na enviada, "Esta mensagem foi
// apagada" na recebida — no lugar do texto do Chatwoot. A apagada PELO CLIENTE é outra
// coisa (SeloApagadaPeloCliente): lá o conteúdo continua à vista da equipe.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import BaseBubble from '../message/bubbles/Base.vue';
import { useMessageContext } from '../message/provider.js';
import { MESSAGE_TYPES } from '../message/constants';

const { messageType } = useMessageContext();
const { t } = useI18n();

const texto = computed(() =>
  messageType.value === MESSAGE_TYPES.INCOMING
    ? t('CONVERSA_CANAL.APAGADA.RECEBIDA')
    : t('CONVERSA_CANAL.APAGADA.ENVIADA')
);
</script>

<template>
  <BaseBubble data-bubble-name="apagada">
    <p
      class="m-0 flex items-start gap-1.5 px-[9px] pt-[6px] pb-[22px] text-[14.2px] leading-[19px] italic text-[#667781] dark:text-[#8696A0]"
      data-apagada-pela-equipe
    >
      <span
        class="i-ph-prohibit size-[18px] mt-px shrink-0"
        aria-hidden="true"
      />
      <span>{{ texto }}</span>
    </p>
  </BaseBubble>
</template>
