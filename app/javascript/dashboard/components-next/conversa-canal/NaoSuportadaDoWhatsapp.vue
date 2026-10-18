<script setup>
// Mensagem que o WhatsApp não deixa ver aqui, com o tipo conhecido (#1702): no lugar do
// aviso amarelo genérico, um balão comum do cliente com o ícone do tipo e o que fazer
// ("O cliente mandou uma enquete. Abra no celular para ver."), em cinza e itálico, como
// os avisos do próprio app. Sem tipo, Message.vue mantém o aviso genérico de sempre.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import BaseBubble from '../message/bubbles/Base.vue';
import { useMessageContext } from '../message/provider.js';
import { tipoNaoSuportado } from './marcasDaMensagem';
import { hybridRecoveryNoteKey } from '../message/helpers/hybridRecovery.js';

const { contentAttributes } = useMessageContext();
const { t } = useI18n();

const ICONES = {
  poll: 'i-ph-chart-bar-horizontal',
  gif: 'i-ph-gif',
  pinned: 'i-ph-push-pin',
  edit: 'i-ph-pencil-simple',
  view_once: 'i-ph-number-circle-one',
  unknown: 'i-ph-device-mobile',
};

// Chaves escritas por extenso: a trava de i18n confere cada uma.
const TEXTOS = {
  poll: 'CONVERSA_CANAL.NAO_SUPORTADA.poll',
  gif: 'CONVERSA_CANAL.NAO_SUPORTADA.gif',
  pinned: 'CONVERSA_CANAL.NAO_SUPORTADA.pinned',
  edit: 'CONVERSA_CANAL.NAO_SUPORTADA.edit',
  view_once: 'CONVERSA_CANAL.NAO_SUPORTADA.view_once',
  unknown: 'CONVERSA_CANAL.NAO_SUPORTADA.unknown',
};

const tipo = computed(() => tipoNaoSuportado(contentAttributes.value));

// chat#1489: o WhatsApp API ainda busca no celular (pending) ou não conseguiu (failed).
// O estado vem em contentAttributes.hybridRecovery (texto); recuperada não chega aqui.
const ESTADOS_DA_RECUPERACAO = ['pending', 'failed'];
const textoDaRecuperacao = computed(() =>
  ESTADOS_DA_RECUPERACAO.includes(contentAttributes.value?.hybridRecovery)
    ? hybridRecoveryNoteKey(contentAttributes.value)
    : null
);
</script>

<template>
  <BaseBubble data-bubble-name="nao-suportada-tipo">
    <p
      class="m-0 flex items-start gap-1.5 px-[9px] pt-[6px] pb-[22px] text-[14.2px] leading-[19px] italic text-[#3B3B3B] dark:text-[#D1D7DB]"
      :data-tipo-nao-suportado="tipo"
    >
      <span
        class="size-[18px] mt-px shrink-0 text-[#8C8C8C] dark:text-[#A7A8A8]"
        :class="ICONES[tipo]"
        aria-hidden="true"
      />
      <span>{{ t(textoDaRecuperacao || TEXTOS[tipo]) }}</span>
    </p>
  </BaseBubble>
</template>
