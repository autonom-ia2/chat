<script setup>
// #1702: a mensagem que o atendente está respondendo, em cima do campo da caixa de
// resposta, como no WhatsApp Web: o mesmo cartão da citação no balão (faixa, nome e
// texto) na largura toda, com o X para desistir. Sem a pele, fica o ReplyToMessage.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Icon from 'next/icon/Icon.vue';
import { useCamelCase } from 'dashboard/composables/useTransformKeys';
import CitacaoDoWhatsapp from './CitacaoDoWhatsapp.vue';
import { previaDoAnexoCitado } from './citacaoDoAnexo';
import { previaDaCitada } from './useFormatoDoWhatsapp';

const props = defineProps({
  // A mensagem da lista da conversa (chaves do servidor, snake_case).
  message: { type: Object, required: true },
});
const emit = defineEmits(['dismiss']);
const { t } = useI18n();

const mensagem = computed(() => useCamelCase(props.message, { deep: true }));
const previa = computed(() => {
  // Lido como o balão da citada o mostra (#1740): do cliente, no formato do app.
  if (mensagem.value.content) return previaDaCitada(mensagem.value);
  // Os mesmos rótulos da citação no balão ("Foto", "Figurinha", o nome do documento).
  return previaDoAnexoCitado(mensagem.value, t);
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
