<script setup>
// Mensagem apagada pela equipe (#1702), como no WhatsApp: o círculo cortado e o aviso
// em cinza e itálico — "Você apagou esta mensagem" na enviada, "Esta mensagem foi
// apagada" na recebida — no lugar do texto do Chatwoot. A apagada PELO CLIENTE é outra
// coisa (SeloApagadaPeloCliente): lá o conteúdo continua à vista da equipe.
// "Você apagou esta mensagem", no app, quer dizer que sumiu para todos: só quando a
// caixa apaga no WhatsApp (WAHA) ou o canal confirmou (revogada_no_canal). Na oficial
// o aviso diz a verdade: apagada só aqui, o cliente ainda vê (apagadaDoWhatsapp.js).
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import BaseBubble from '../message/bubbles/Base.vue';
import { useMessageContext } from '../message/provider.js';
import { MESSAGE_TYPES } from '../message/constants';
import { apagadaParaTodos } from './apagadaDoWhatsapp';

const { messageType, contentAttributes, inboxId } = useMessageContext();
const { t } = useI18n();
const caixaPorId = useMapGetter('inboxes/getInbox');

const recebida = computed(() => messageType.value === MESSAGE_TYPES.INCOMING);
const soAqui = computed(
  () =>
    !recebida.value &&
    !apagadaParaTodos({
      caixa: caixaPorId.value(inboxId?.value),
      contentAttributes: contentAttributes.value,
    })
);

const texto = computed(() => {
  if (recebida.value) return t('CONVERSA_CANAL.APAGADA.RECEBIDA');
  return soAqui.value
    ? t('CONVERSA_CANAL.APAGADA.ENVIADA_SO_AQUI')
    : t('CONVERSA_CANAL.APAGADA.ENVIADA');
});
</script>

<template>
  <BaseBubble data-bubble-name="apagada">
    <p
      class="m-0 flex items-start gap-1.5 px-[9px] pt-[6px] pb-[22px] text-[14.2px] leading-[19px] italic text-[#667781] dark:text-[#8696A0]"
      data-apagada-pela-equipe
      :data-apagada-so-aqui="soAqui ? '' : undefined"
    >
      <span
        class="i-ph-prohibit size-[18px] mt-px shrink-0"
        aria-hidden="true"
      />
      <span>{{ texto }}</span>
    </p>
  </BaseBubble>
</template>
