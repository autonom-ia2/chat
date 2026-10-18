<script setup>
// #1809 — a barra de baixo do e-mail na gaveta "Escrever": a mesma da resposta de
// e-mail nova (ReplyBottomPanel), com os mesmos componentes, o mesmo desenho e a
// mesma ordem. "+" (Documento, Fotos e vídeos) anexa; o emoji abre a janela de
// emojis em cima da barra; o microfone dita e o texto entra no editor; a assinatura
// liga e desliga para a caixa (a mesma chave da resposta). Fora da conversa não há
// "Modelo de e-mail" no "+": ele preenche os campos pela conversa.
import { ref, useTemplateRef } from 'vue';
import { useUISettings } from 'dashboard/composables/useUISettings';
import NextButton from 'dashboard/components-next/button/Button.vue';
import MaisDoEmail from 'dashboard/components-next/conversa-canal/email/MaisDoEmail.vue';
import JanelaDeEmojis from 'dashboard/components-next/conversa-canal/email/JanelaDeEmojis.vue';
import BotaoDeAudio from 'dashboard/components-next/conversa-canal/email/BotaoDeAudio.vue';
import { BOTOES_DA_BARRA } from 'dashboard/components-next/conversa-canal/email/visualEmail';
import { anexarArquivos } from 'dashboard/components-next/conversa-canal/usePeleDaResposta';
import { useAnexarNaNovaConversa } from './useAnexarNaNovaConversa';

const props = defineProps({
  canal: { type: Object, required: true },
  comAssinatura: { type: Boolean, default: false },
});
const emit = defineEmits(['inserir']);

const anexos = defineModel('anexos', { type: Array, default: () => [] });

const { onFileUpload } = useAnexarNaNovaConversa(anexos);
const { setSignatureFlagForInbox } = useUISettings();

const barra = useTemplateRef('barra');
const comEmojis = ref(false);

const inserir = texto => emit('inserir', texto);
const alternarAssinatura = () =>
  setSignatureFlagForInbox(props.canal.channelType, !props.comAssinatura);
</script>

<template>
  <!-- Toque de 44 px na gaveta (a resposta usa 40). -->
  <div
    class="flex items-center border-t border-n-weak px-3 py-2 [&_.left-wrap_button:not([role=menuitem]):not([data-livre])]:!size-11"
    :class="BOTOES_DA_BARRA"
    data-barra-do-email
  >
    <div
      ref="barra"
      role="toolbar"
      :aria-label="$t('NOVA_CONVERSA.MENSAGEM.FERRAMENTAS')"
      class="left-wrap flex flex-wrap items-center"
    >
      <MaisDoEmail
        :com-modelos="false"
        @arquivos="escolha => anexarArquivos(escolha, onFileUpload)"
      />
      <NextButton
        v-tooltip.top-end="$t('CONVERSATION.REPLYBOX.TIP_EMOJI_ICON')"
        :aria-label="$t('CONVERSATION.REPLYBOX.TIP_EMOJI_ICON')"
        :aria-expanded="comEmojis"
        icon="i-ph-smiley-sticker"
        slate
        faded
        sm
        data-emoji-do-email
        @click="comEmojis = !comEmojis"
      />
      <BotaoDeAudio :inserir="inserir" />
      <NextButton
        v-tooltip.top-end="
          comAssinatura
            ? $t('CONVERSATION.FOOTER.DISABLE_SIGN_TOOLTIP')
            : $t('CONVERSATION.FOOTER.ENABLE_SIGN_TOOLTIP')
        "
        :aria-label="
          comAssinatura
            ? $t('CONVERSATION.FOOTER.DISABLE_SIGN_TOOLTIP')
            : $t('CONVERSATION.FOOTER.ENABLE_SIGN_TOOLTIP')
        "
        :aria-pressed="comAssinatura"
        :data-ligado="comAssinatura || undefined"
        icon="i-ph-signature"
        slate
        faded
        sm
        data-assinatura-do-email
        @click="alternarAssinatura"
      />
    </div>
    <JanelaDeEmojis
      v-if="comEmojis"
      :ancora="barra"
      @escolher="inserir"
      @fechar="comEmojis = false"
    />
  </div>
</template>
