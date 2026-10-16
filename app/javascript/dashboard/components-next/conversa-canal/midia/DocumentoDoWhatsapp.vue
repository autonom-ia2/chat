<script setup>
// Documento no balão com a cara do WhatsApp (#1702): o cartão do app, com o ícone do
// tipo (PDF em vermelho), o nome, "PDF • 107 KB" e o botão de baixar à direita.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMessageContext } from '../../message/provider.js';
import { idiomaDoPainel } from '../dataDaConversa';
import {
  extensaoDoArquivo,
  nomeDoArquivo,
  resumoDoArquivo,
} from './tamanhoDoArquivo';

const { t, locale } = useI18n();
const { attachments, orientation } = useMessageContext();

const anexo = computed(() => attachments.value?.[0] || {});
const nome = computed(
  () => nomeDoArquivo(anexo.value) || t('CONVERSATION.UNKNOWN_FILE_TYPE')
);
const extensao = computed(() => extensaoDoArquivo(anexo.value).slice(0, 4));
const resumo = computed(() =>
  resumoDoArquivo(anexo.value, idiomaDoPainel(locale.value))
);
const ehPdf = computed(() => extensao.value === 'PDF');
const enviada = computed(() => orientation?.value === 'right');
</script>

<template>
  <div
    class="flex items-center gap-3 w-full min-w-0 px-3 py-[13px] rounded-[8px]"
    :class="
      enviada
        ? 'bg-[#D1F4CC] dark:bg-[#103E2A]'
        : 'bg-[#F5F5F5] dark:bg-[#1D1F1F]'
    "
    data-documento-do-whatsapp
  >
    <svg
      viewBox="0 0 26 32"
      class="w-[26px] h-8 flex-shrink-0"
      aria-hidden="true"
      :class="ehPdf ? 'text-[#E2453C]' : 'text-[#8C8C8C] dark:text-[#6B6E6E]'"
    >
      <path
        d="M3 0h14l9 9v20a3 3 0 0 1-3 3H3a3 3 0 0 1-3-3V3a3 3 0 0 1 3-3Z"
        fill="currentColor"
      />
      <path d="M17 0v6a3 3 0 0 0 3 3h6Z" fill="white" fill-opacity="0.35" />
      <text
        x="13"
        y="25"
        text-anchor="middle"
        font-size="7"
        font-weight="700"
        fill="white"
      >
        {{ extensao }}
      </text>
    </svg>
    <div class="flex flex-col flex-1 min-w-0">
      <span
        class="truncate text-[15px] leading-5 text-[#0A0A0A] dark:text-[#FAFAFA]"
        :title="nome"
      >
        {{ nome }}
      </span>
      <span
        v-if="resumo"
        class="text-[12px] leading-4 text-[#666666] dark:text-[#A7A8A8]"
      >
        {{ resumo }}
      </span>
    </div>
    <a
      v-if="anexo.dataUrl"
      :href="anexo.dataUrl"
      target="_blank"
      rel="noreferrer noopener nofollow"
      class="grid place-content-center size-10 flex-shrink-0 rounded-full text-[#8C8C8C] dark:text-[#A7A8A8] hover:bg-[#000]/5 dark:hover:bg-white/5 skip-context-menu"
      :aria-label="t('CONVERSA_CANAL.MIDIA.BAIXAR', { nome })"
      @click.stop
    >
      <span class="i-ph-download-simple size-7" aria-hidden="true" />
    </a>
  </div>
</template>
