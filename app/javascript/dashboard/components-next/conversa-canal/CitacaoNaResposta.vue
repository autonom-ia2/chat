<script setup>
// #1702: a mensagem que o atendente está respondendo, em cima do campo da caixa de
// resposta, como no WhatsApp Web: o mesmo cartão da citação no balão (faixa, nome e
// texto) na largura toda, com o X para desistir. Sem a pele, fica o ReplyToMessage.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Icon from 'next/icon/Icon.vue';
import MessageFormatter from 'shared/helpers/MessageFormatter.js';
import { useCamelCase } from 'dashboard/composables/useTransformKeys';
import CitacaoDoWhatsapp from './CitacaoDoWhatsapp.vue';
import { eFigurinha } from './figurinha';

const props = defineProps({
  // A mensagem da lista da conversa (chaves do servidor, snake_case).
  message: { type: Object, required: true },
});
const emit = defineEmits(['dismiss']);
const { t } = useI18n();

// Chaves escritas por extenso: a trava de i18n confere cada uma.
const NOMES_DO_ANEXO = {
  image: 'CONVERSA_CANAL.CITACAO.FOTO',
  video: 'CONVERSA_CANAL.CITACAO.VIDEO',
  audio: 'CONVERSA_CANAL.CITACAO.AUDIO',
  file: 'CONVERSA_CANAL.CITACAO.DOCUMENTO',
  location: 'CONVERSA_CANAL.CITACAO.LOCALIZACAO',
  contact: 'CONVERSA_CANAL.CITACAO.CONTATO',
};

const mensagem = computed(() => useCamelCase(props.message, { deep: true }));
const previa = computed(() => {
  const { content, attachments } = mensagem.value;
  if (content) return new MessageFormatter(content).formattedMessage;
  // A figurinha é anexo de imagem; o balão a chama de Figurinha, a citação também.
  if (eFigurinha(attachments?.[0])) return t('CONVERSA_CANAL.MIDIA.FIGURINHA');
  const chave = NOMES_DO_ANEXO[attachments?.[0]?.fileType];
  return t(chave || 'CONVERSA_CANAL.CITACAO.SEM_TEXTO');
});
</script>

<template>
  <div
    class="flex items-start gap-1 basis-full !w-full pb-2"
    data-citacao-na-resposta
  >
    <CitacaoDoWhatsapp
      :mensagem="mensagem"
      :previa="previa"
      inerte
      class="!mb-0"
    />
    <button
      type="button"
      class="grid place-content-center size-8 shrink-0 rounded-full text-[#666666] dark:text-[#A7A8A8] hover:bg-[#0A0A0A]/5 dark:hover:bg-white/5"
      :aria-label="t('CONVERSATION.REPLYBOX.DISMISS_REPLY')"
      @click.stop="emit('dismiss')"
    >
      <Icon icon="i-ph-x" class="size-5" />
    </button>
  </div>
</template>
