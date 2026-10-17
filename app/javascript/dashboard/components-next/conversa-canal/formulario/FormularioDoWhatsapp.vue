<script setup>
// Formulário do WhatsApp (Flows, #1473) na conversa com a cara do WhatsApp (#1702),
// como o cliente vê no celular: cabeçalho, corpo, rodapé e, separado por uma linha
// fina, o botão verde com ícone que abre o formulário. O botão não abre nada no
// painel (o formulário só roda no WhatsApp do cliente). Embaixo, só para a equipe:
// o nome do formulário e, quando o cliente já respondeu, o atalho para a resposta.
// Se o envio falhou, o botão fica apagado e o motivo aparece embaixo do balão
// (MessageError), como em qualquer mensagem.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Icon from 'next/icon/Icon.vue';
import { useMapGetter } from 'dashboard/composables/store';
import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import BaseBubble from '../../message/bubbles/Base.vue';
import FormattedContent from '../../message/bubbles/Text/FormattedContent.vue';
import MessageMeta from '../../message/MessageMeta.vue';
import { useMessageContext } from '../../message/provider.js';
import { MESSAGE_STATUS } from '../../message/constants';
import { classesDaHora } from '../visualWhatsapp';
import { respostaDoFormularioPara } from './respostaDoFormulario';

defineProps({
  header: { type: String, default: '' },
  footer: { type: String, default: '' },
  cta: { type: String, default: '' },
  nome: { type: String, default: '' },
});

const { t } = useI18n();
const { id, content, status, variant } = useMessageContext();
const conversa = useMapGetter('getSelectedChat');

const falhou = computed(() => status.value === MESSAGE_STATUS.FAILED);
const resposta = computed(() =>
  respostaDoFormularioPara(id.value, conversa.value?.messages)
);
const hora = computed(() =>
  classesDaHora({ variante: variant.value, nomeDoBalao: '' })
);

const irParaResposta = () =>
  emitter.emit(BUS_EVENTS.SCROLL_TO_MESSAGE, {
    messageId: resposta.value.id,
  });
</script>

<template>
  <div class="w-[320px] max-w-full" data-formulario-do-whatsapp>
    <BaseBubble
      class="!px-[9px] !pt-[6px] !pb-0 text-[14.2px] leading-[19px]"
      data-bubble-name="rich-flow"
      hide-meta
    >
      <div v-if="header" class="font-semibold break-words">{{ header }}</div>
      <FormattedContent v-if="content" :content="content" />
      <div
        v-if="footer"
        class="text-[13px] text-[#666666] dark:text-[#A7A8A8] break-words"
      >
        {{ footer }}
      </div>
      <div
        class="mt-1 flex flex-wrap items-center gap-x-2 gap-y-0.5 text-xs text-[#666666] dark:text-[#A7A8A8]"
      >
        <span class="inline-flex items-center gap-1 min-w-0 break-words">
          <Icon icon="i-ph-clipboard-text" class="size-3.5 flex-shrink-0" />
          {{
            nome
              ? t('CONVERSA_CANAL.FORMULARIO.NOME', { nome })
              : t('CONVERSA_CANAL.FORMULARIO.SEM_NOME')
          }}
        </span>
        <button
          v-if="resposta"
          type="button"
          class="inline-flex items-center gap-1 min-h-11 font-medium text-[#1A6B42] dark:text-[#6FD07E] hover:underline"
          data-ir-para-resposta
          @click="irParaResposta"
        >
          <Icon icon="i-ph-check-bold" class="size-3.5" />
          {{ t('CONVERSA_CANAL.FORMULARIO.RESPONDIDO') }}
        </button>
      </div>
      <MessageMeta :class="hora" class="pb-1" />
      <div
        v-if="cta"
        class="flex items-center justify-center gap-1.5 w-[calc(100%+18px)] -mx-[9px] min-h-[42px] px-3 border-t border-[#0A0A0A]/10 dark:border-white/10 text-[14.2px] font-medium"
        :class="
          falhou
            ? 'text-[#666666]/60 dark:text-[#A7A8A8]/60'
            : 'text-[#1A6B42] dark:text-[#6FD07E]'
        "
        :aria-disabled="falhou || undefined"
        data-botao-do-formulario
      >
        <Icon icon="i-ph-note-pencil" class="size-[18px] flex-shrink-0" />
        <span class="min-w-0 break-words">{{ cta }}</span>
        <span class="sr-only">
          {{ t('RICH_MESSAGE.FLOW.OPENS_ON_CUSTOMER_PHONE') }}
        </span>
      </div>
    </BaseBubble>
  </div>
</template>
