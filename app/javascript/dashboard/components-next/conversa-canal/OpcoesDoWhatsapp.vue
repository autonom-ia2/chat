<script setup>
// Opções (#1473) na conversa com a cara do WhatsApp (#1702), como o cliente vê no app:
// até 3 opções são botões soltos embaixo do balão, cada um na sua caixinha com a seta
// de resposta; mais que isso é uma lista que fica fechada atrás do botão do balão (um
// toque abre a lista, como a folha do app). A opção que o cliente tocou leva o visto.
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Icon from 'next/icon/Icon.vue';
import BaseBubble from '../message/bubbles/Base.vue';
import FormattedContent from '../message/bubbles/Text/FormattedContent.vue';
import OptionsList from '../message/bubbles/RichMessage/OptionsList.vue';
import MessageMeta from '../message/MessageMeta.vue';
import { useMessageContext } from '../message/provider.js';
import { classesDaHora } from './visualWhatsapp';

defineProps({
  header: { type: String, default: '' },
  footer: { type: String, default: '' },
  isList: { type: Boolean, default: false },
  listButton: { type: String, default: '' },
  options: { type: Array, required: true },
  sections: { type: Array, required: true },
  chosenId: { type: String, default: '' },
  chosenLine: { type: String, default: '' },
});

const { t } = useI18n();
const { content } = useMessageContext();
const listaAberta = ref(false);
// A hora fica dentro do balão, antes do botão da lista, como no app.
const HORA = classesDaHora({ variante: 'agent', nomeDoBalao: '' });

const CAIXINHA =
  'flex items-center justify-center gap-1.5 w-full min-h-[42px] px-3 rounded-[7.5px] bg-[#D9FDD3] dark:bg-[#005C4B] text-[#027EB5] dark:text-[#53BDEB] text-[14.2px] font-medium shadow-[0_1px_0.5px_rgba(11,20,26,0.13)]';
const LINHA_DO_BALAO =
  'flex items-center justify-center gap-1.5 w-full min-h-[42px] -mb-[8px] mt-1.5 border-t border-[#111B21]/10 dark:border-white/10 text-[#027EB5] dark:text-[#53BDEB] text-[14.2px] font-medium';
</script>

<template>
  <div
    class="flex flex-col gap-[2px] w-[300px] max-w-full"
    data-opcoes-do-whatsapp
  >
    <BaseBubble
      class="px-[9px] pt-[6px] pb-[8px] text-[14.2px] leading-[19px]"
      data-bubble-name="rich-options"
      hide-meta
    >
      <span class="sr-only">{{ t('RICH_MESSAGE.OPTIONS.MIRROR') }}</span>
      <div v-if="header" class="font-medium break-words">{{ header }}</div>
      <FormattedContent v-if="content" :content="content" />
      <div
        v-if="footer"
        class="text-[13px] text-[#667781] dark:text-[#8696A0] break-words"
      >
        {{ footer }}
      </div>
      <div
        v-if="chosenLine"
        class="mt-1 text-xs text-[#667781] dark:text-[#8696A0] break-words"
      >
        {{ chosenLine }}
      </div>
      <MessageMeta :class="HORA" />
      <button
        v-if="isList"
        type="button"
        :class="LINHA_DO_BALAO"
        :aria-expanded="listaAberta"
        data-abrir-lista
        @click="listaAberta = !listaAberta"
      >
        <Icon icon="i-ph-list-bullets-bold" class="size-4" />
        {{ listButton }}
      </button>
    </BaseBubble>

    <template v-if="!isList">
      <div
        v-for="(option, index) in options"
        :key="index"
        :class="CAIXINHA"
        data-option-button
      >
        <Icon
          :icon="
            chosenId && option.id === chosenId
              ? 'i-ph-check-bold'
              : 'i-ph-arrow-bend-up-left-bold'
          "
          class="size-4 flex-shrink-0"
        />
        <span class="min-w-0 break-words">{{ option.title }}</span>
      </div>
    </template>
    <OptionsList
      v-else-if="listaAberta"
      :sections="sections"
      :chosen-id="chosenId"
      class="!bg-white dark:!bg-[#233138] !border-0 shadow-[0_2px_5px_rgba(11,20,26,0.26)]"
    />
  </div>
</template>
