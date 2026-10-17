<script setup>
// Opções (#1473) na conversa com a cara do WhatsApp (#1702), como no WhatsApp Web:
// até 3 opções são linhas de botão dentro do balão, com a seta de resposta; mais que
// isso é "Ver opções", que abre a janela da lista presa à esquerda da conversa. A
// opção que o cliente tocou leva o visto (botão) ou o rádio marcado (lista).
import { nextTick, ref, useTemplateRef } from 'vue';
import { useI18n } from 'vue-i18n';
import Icon from 'next/icon/Icon.vue';
import BaseBubble from '../message/bubbles/Base.vue';
import FormattedContent from '../message/bubbles/Text/FormattedContent.vue';
import MessageMeta from '../message/MessageMeta.vue';
import { useMessageContext } from '../message/provider.js';
import { classesDaHora } from './visualWhatsapp';

const props = defineProps({
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
const raiz = useTemplateRef('raiz');
const fechar = useTemplateRef('fechar');
const abrir = useTemplateRef('abrir');
// A janela da lista abre por cima da conversa, presa à esquerda do painel, como no app.
const alvo = ref(null);
const listaAberta = ref(false);
// A hora fica dentro do balão, acima dos botões, como no app.
const HORA = classesDaHora({ variante: 'agent', nomeDoBalao: '' });

const abrirLista = async () => {
  alvo.value =
    raiz.value?.closest('.conversation-panel')?.parentElement || null;
  listaAberta.value = true;
  await nextTick();
  fechar.value?.focus();
};
// Ao fechar, o foco volta para "Ver opções", de onde a pessoa saiu.
const fecharLista = async () => {
  listaAberta.value = false;
  await nextTick();
  abrir.value?.focus();
};
// A janela é modal e o único controle dela é o fechar: o Tab não sai para a conversa.
const prenderFoco = () => fechar.value?.focus();

const escolhida = option =>
  Boolean(props.chosenId) && option.id === props.chosenId;

// Botão do balão (resposta e "Ver opções"): linha de ponta a ponta, texto verde no meio.
const LINHA_DO_BALAO =
  'flex items-center justify-center gap-1.5 w-[calc(100%+18px)] -mx-[9px] min-h-[42px] px-3 border-t border-[#0A0A0A]/10 dark:border-white/10 text-[#1A6B42] dark:text-[#6FD07E] text-[14.2px] font-medium';
</script>

<template>
  <div ref="raiz" class="w-[320px] max-w-full" data-opcoes-do-whatsapp>
    <BaseBubble
      class="!px-[9px] !pt-[6px] !pb-0 text-[14.2px] leading-[19px]"
      data-bubble-name="rich-options"
      hide-meta
    >
      <span class="sr-only">{{ t('RICH_MESSAGE.OPTIONS.MIRROR') }}</span>
      <div v-if="header" class="font-semibold break-words">{{ header }}</div>
      <FormattedContent v-if="content" :content="content" />
      <div
        v-if="footer"
        class="text-[13px] text-[#666666] dark:text-[#A7A8A8] break-words"
      >
        {{ footer }}
      </div>
      <div
        v-if="chosenLine"
        class="mt-1 text-xs text-[#666666] dark:text-[#A7A8A8] break-words"
      >
        {{ chosenLine }}
      </div>
      <MessageMeta :class="HORA" class="pb-1" />
      <button
        v-if="isList"
        ref="abrir"
        type="button"
        :class="LINHA_DO_BALAO"
        aria-haspopup="dialog"
        :aria-expanded="listaAberta"
        data-abrir-lista
        @click="abrirLista"
      >
        <Icon icon="i-ph-list-bullets" class="size-5" />
        {{ listButton || t('CONVERSA_CANAL.MIDIA.VER_OPCOES') }}
      </button>
      <template v-else>
        <div
          v-for="(option, index) in options"
          :key="index"
          :class="LINHA_DO_BALAO"
          data-option-button
        >
          <Icon
            :icon="
              escolhida(option) ? 'i-ph-check-bold' : 'i-ph-arrow-bend-up-left'
            "
            class="size-[18px] flex-shrink-0"
          />
          <span class="min-w-0 break-words">{{ option.title }}</span>
        </div>
      </template>
    </BaseBubble>

    <Teleport v-if="listaAberta && alvo" :to="alvo">
      <div
        class="absolute inset-0 z-40 bg-[#000]/35"
        data-fundo-da-lista
        @click="fecharLista"
      />
      <div
        role="dialog"
        aria-modal="true"
        :aria-label="listButton || t('CONVERSA_CANAL.MIDIA.VER_OPCOES')"
        class="absolute z-50 top-3 bottom-3 ltr:left-3 rtl:right-3 w-[417px] max-w-[calc(100%-24px)] flex flex-col overflow-hidden rounded-[24px] bg-white dark:bg-[#242626] shadow-[0_4px_24px_rgba(0,0,0,0.2)]"
        data-janela-da-lista
        @keydown.esc="fecharLista"
        @keydown.tab.prevent="prenderFoco"
      >
        <div class="flex items-center gap-6 h-16 px-6 flex-shrink-0">
          <button
            ref="fechar"
            type="button"
            class="grid place-content-center size-10 -ms-2 rounded-full text-[#0A0A0A] dark:text-[#FAFAFA] hover:bg-[#000]/5 dark:hover:bg-white/5"
            :aria-label="t('CONVERSA_CANAL.MIDIA.FECHAR')"
            @click="fecharLista"
          >
            <Icon icon="i-ph-x" class="size-6" />
          </button>
          <span class="text-[16px] text-[#0A0A0A] dark:text-[#FAFAFA]">
            {{ listButton || t('CONVERSA_CANAL.MIDIA.VER_OPCOES') }}
          </span>
        </div>
        <div class="flex-1 overflow-y-auto px-3 pb-4">
          <div
            v-for="(section, indice) in sections"
            :key="indice"
            :role="section.title ? 'group' : undefined"
            :aria-label="section.title || undefined"
          >
            <div
              v-if="section.title"
              aria-hidden="true"
              class="px-3 pt-5 pb-4 text-[13px] font-medium text-[#666666] dark:text-[#A7A8A8]"
            >
              {{ section.title }}
            </div>
            <ul>
              <li
                v-for="(option, linha) in section.options"
                :key="linha"
                class="flex items-center gap-4 min-h-[64px] px-3 py-3 rounded-[10px] hover:bg-[#F4F2F3] dark:hover:bg-white/5"
                data-option-row
              >
                <div class="flex-1 min-w-0">
                  <div
                    class="text-[16px] text-[#0A0A0A] dark:text-[#FAFAFA] break-words"
                  >
                    {{ option.title }}
                  </div>
                  <div
                    v-if="option.description"
                    class="text-[13px] text-[#666666] dark:text-[#A7A8A8] break-words"
                  >
                    {{ option.description }}
                  </div>
                </div>
                <span
                  class="grid place-content-center size-5 flex-shrink-0 rounded-full border-2"
                  :class="
                    escolhida(option)
                      ? 'border-[#0A0A0A] dark:border-[#FAFAFA]'
                      : 'border-[#8C8C8C]'
                  "
                  :aria-label="
                    escolhida(option)
                      ? t('CONVERSA_CANAL.MIDIA.ESCOLHIDA')
                      : undefined
                  "
                >
                  <span
                    v-if="escolhida(option)"
                    class="size-2.5 rounded-full bg-[#0A0A0A] dark:bg-[#FAFAFA]"
                  />
                </span>
              </li>
            </ul>
          </div>
        </div>
      </div>
    </Teleport>
  </div>
</template>
