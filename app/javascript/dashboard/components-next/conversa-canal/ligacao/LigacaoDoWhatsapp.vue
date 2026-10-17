<script setup>
// Registro de ligação com a cara do WhatsApp (#1702): um balão do lado do cliente com o
// ícone num círculo (telefone ou câmera), "Ligação de voz perdida" em vermelho quando
// ninguém atendeu ou foi recusada, e a hora embaixo. Quem escolhe é Message.vue, com a
// pele, para a mensagem de aviso que traz waha_call_summary. Retornar a ligação não
// existe pelo painel (a API não liga): o cartão só informa.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMessageContext } from '../../message/provider.js';
import { useHoraDaPele } from '../useHoraDaPele';
import { ligacaoPerdida, resumoDaLigacao } from './ligacao';

const { contentAttributes, createdAt } = useMessageContext();
const { t } = useI18n();

const resumo = computed(() => resumoDaLigacao(contentAttributes.value));
const perdida = computed(() => ligacaoPerdida(resumo.value));
const hora = useHoraDaPele(
  computed(() => resumo.value?.quando || createdAt.value)
);

// Chaves escritas por extenso: a trava de i18n confere cada uma.
const CHAVES = {
  missed: {
    voz: 'CONVERSA_CANAL.LIGACAO.VOZ_PERDIDA',
    video: 'CONVERSA_CANAL.LIGACAO.VIDEO_PERDIDA',
  },
  rejected: {
    voz: 'CONVERSA_CANAL.LIGACAO.VOZ_RECUSADA',
    video: 'CONVERSA_CANAL.LIGACAO.VIDEO_RECUSADA',
  },
  accepted: {
    voz: 'CONVERSA_CANAL.LIGACAO.VOZ',
    video: 'CONVERSA_CANAL.LIGACAO.VIDEO',
  },
};

const titulo = computed(() => {
  const { resultado, video } = resumo.value;
  return t(CHAVES[resultado][video ? 'video' : 'voz']);
});

const icone = computed(() => {
  if (resumo.value.video) return 'i-ph-video-camera-fill';
  return perdida.value ? 'i-ph-phone-x-fill' : 'i-ph-phone-incoming-fill';
});
</script>

<template>
  <div
    class="flex items-center gap-3 w-[260px] max-w-full py-2 ps-2 pe-3 rounded-[10px] bg-white dark:bg-[#242626] shadow-[0_1px_0.5px_rgba(11,20,26,0.13)]"
    role="note"
    :aria-label="hora ? `${titulo}, ${hora}` : titulo"
    data-ligacao-do-whatsapp
  >
    <span
      class="grid place-content-center size-10 shrink-0 rounded-full"
      :class="
        perdida
          ? 'bg-[#FDE7E9] dark:bg-[#3B1F24] text-[#EA0038] dark:text-[#F15C6D]'
          : 'bg-[#0A0A0A]/[0.06] dark:bg-white/10 text-[#3B3B3B] dark:text-[#FAFAFA]'
      "
      aria-hidden="true"
    >
      <span class="size-5" :class="icone" />
    </span>
    <span class="min-w-0" aria-hidden="true">
      <span
        class="block text-[14.2px] leading-[19px] font-medium"
        :class="
          perdida
            ? 'text-[#EA0038] dark:text-[#F15C6D]'
            : 'text-[#0A0A0A] dark:text-[#FAFAFA]'
        "
        data-titulo-da-ligacao
      >
        {{ titulo }}
      </span>
      <span
        v-if="hora"
        class="block text-[12px] text-[#666666] dark:text-[#A7A8A8]"
      >
        {{ hora }}
      </span>
    </span>
  </div>
</template>
