<script setup>
// #1988 — a barra de baixo da caixa do WhatsApp na gaveta "Enviar mensagem", no
// padrão da barra do e-mail (NovaConversaBarraDoEmail) e com os botões da caixa de
// resposta: "+" (Documento, Fotos e vídeos) anexa; o emoji abre a janela de emojis em
// cima da barra; o microfone grava áudio (sai como mensagem de voz); a assinatura liga
// e desliga para a caixa (a mesma chave da resposta). Pelo número reserva também: o WAHA
// manda arquivo e voz.
import { computed, ref, useTemplateRef } from 'vue';
import { useUISettings } from 'dashboard/composables/useUISettings';
import { useMapGetter } from 'dashboard/composables/store';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import NextButton from 'dashboard/components-next/button/Button.vue';
import MaisDoEmail from 'dashboard/components-next/conversa-canal/email/MaisDoEmail.vue';
import JanelaDeEmojis from 'dashboard/components-next/emoji/JanelaDeEmojis.vue';
import { BOTOES_DA_BARRA } from 'dashboard/components-next/conversa-canal/email/visualEmail';
import { anexarArquivos } from 'dashboard/components-next/conversa-canal/usePeleDaResposta';
import { useAnexarNaNovaConversa } from './useAnexarNaNovaConversa';

const props = defineProps({
  canal: { type: Object, required: true },
  comAssinatura: { type: Boolean, default: false },
});
const emit = defineEmits(['inserir', 'gravar']);

const anexos = defineModel('anexos', { type: Array, default: () => [] });

const { onFileUpload } = useAnexarNaNovaConversa(anexos);
const { setSignatureFlagForInbox } = useUISettings();

// O microfone segue a mesma chave da conta que a caixa de resposta (ReplyBottomPanel).
const contaAtual = useMapGetter('getCurrentAccountId');
const temChave = useMapGetter('accounts/isFeatureEnabledonAccount');
const podeGravar = computed(() =>
  Boolean(temChave.value(contaAtual.value, FEATURE_FLAGS.VOICE_RECORDER))
);

const barra = useTemplateRef('barra');
const comEmojis = ref(false);

const alternarAssinatura = () =>
  setSignatureFlagForInbox(props.canal.channelType, !props.comAssinatura);
</script>

<template>
  <!-- Toque de 44 px na gaveta (a resposta usa 40). -->
  <div
    class="flex items-center px-3 py-2 [&_.left-wrap_button:not([role=menuitem])]:!size-11"
    :class="BOTOES_DA_BARRA"
    data-barra-do-whatsapp
  >
    <div
      ref="barra"
      role="toolbar"
      :aria-label="$t('NOVA_CONVERSA.MENSAGEM.FERRAMENTAS_WHATSAPP')"
      class="left-wrap flex flex-wrap items-center"
    >
      <MaisDoEmail
        :com-modelos="false"
        local
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
        data-emoji-do-whatsapp
        @click="comEmojis = !comEmojis"
      />
      <NextButton
        v-if="podeGravar"
        v-tooltip.top-end="$t('CONVERSATION.REPLYBOX.TIP_AUDIORECORDER_ICON')"
        :aria-label="$t('CONVERSATION.REPLYBOX.TIP_AUDIORECORDER_ICON')"
        icon="i-ph-microphone"
        slate
        faded
        sm
        data-gravar-do-whatsapp
        @click="emit('gravar')"
      />
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
        data-assinatura-do-whatsapp
        @click="alternarAssinatura"
      />
    </div>
    <JanelaDeEmojis
      v-if="comEmojis"
      :ancora="barra"
      @escolher="texto => emit('inserir', texto)"
      @fechar="comEmojis = false"
    />
  </div>
</template>
