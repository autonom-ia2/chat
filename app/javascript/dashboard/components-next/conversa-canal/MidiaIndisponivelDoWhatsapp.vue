<script setup>
// Mídia do cliente que não chegou (#1709, `media_unavailable`): no lugar da foto, do
// vídeo, do áudio ou do documento, um aviso cinza com o ícone do tipo ("Não foi
// possível baixar esta foto"), como o app mostra a mídia que não baixou. Embaixo fica
// o texto da mensagem: a legenda do cliente ou o aviso do servidor ("peça para
// reenviar"). Quem escolhe é balaoDaPele, só com a pele.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import BaseBubble from '../message/bubbles/Base.vue';
import { useMessageContext } from '../message/provider.js';
import { MIDIA_INDISPONIVEL } from './visualWhatsapp';
import { midiaIndisponivel } from './marcasDaMensagem';

const { content, contentAttributes } = useMessageContext();
const { t } = useI18n();

const ICONES = {
  voice: 'i-ph-microphone',
  audio: 'i-ph-headphones',
  image: 'i-ph-camera',
  video: 'i-ph-video-camera',
  document: 'i-ph-file',
  sticker: 'i-ph-sticker',
};

// Chaves escritas por extenso: a trava de i18n confere cada uma.
const TEXTOS = {
  voice: 'CONVERSA_CANAL.MIDIA_INDISPONIVEL.voice',
  audio: 'CONVERSA_CANAL.MIDIA_INDISPONIVEL.audio',
  image: 'CONVERSA_CANAL.MIDIA_INDISPONIVEL.image',
  video: 'CONVERSA_CANAL.MIDIA_INDISPONIVEL.video',
  document: 'CONVERSA_CANAL.MIDIA_INDISPONIVEL.document',
  sticker: 'CONVERSA_CANAL.MIDIA_INDISPONIVEL.sticker',
};

const indisponivel = computed(() => midiaIndisponivel(contentAttributes.value));
const texto = computed(() =>
  indisponivel.value?.mostrarTexto && typeof content.value === 'string'
    ? content.value.trim()
    : ''
);
</script>

<template>
  <BaseBubble :data-bubble-name="MIDIA_INDISPONIVEL">
    <div
      class="px-[9px] pt-[6px] pb-[22px] text-[14.2px] leading-[19px]"
      :data-midia-indisponivel="indisponivel.tipo"
    >
      <p
        class="m-0 flex items-center gap-2 px-2 py-2 rounded-[7.5px] bg-[#0A0A0A]/[0.05] dark:bg-white/[0.06] italic text-[#3B3B3B] dark:text-[#D1D7DB]"
      >
        <span
          class="size-[18px] shrink-0 text-[#666666] dark:text-[#A7A8A8]"
          :class="ICONES[indisponivel.tipo]"
          aria-hidden="true"
        />
        <span>{{ t(TEXTOS[indisponivel.tipo]) }}</span>
      </p>
      <p
        v-if="texto"
        class="m-0 pt-1.5 break-words whitespace-pre-wrap"
        data-texto-da-midia-indisponivel
      >
        {{ texto }}
      </p>
    </div>
  </BaseBubble>
</template>
