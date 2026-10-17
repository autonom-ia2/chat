<script setup>
// Documento no balão com a cara do WhatsApp (#1702): o cartão do app, com o ícone do
// tipo (PDF em vermelho), o nome, "PDF • 107 KB" e o botão de baixar à direita, um
// link direto que pede ao Active Storage o download com o nome do arquivo. PDF com
// prévia mostra a 1ª página em cima e a faixa embaixo, como o app.
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMessageContext } from '../../message/provider.js';
import { idiomaDoPainel } from '../dataDaConversa';
import {
  extensaoDoArquivo,
  nomeDoArquivo,
  resumoDoArquivo,
} from './tamanhoDoArquivo';
import { doActiveStorage, enderecoParaBaixar } from './enderecoParaBaixar';

// `anexo`: o documento de uma legenda (balão de texto); sem ele, o primeiro do balão.
const props = defineProps({ anexo: { type: Object, default: null } });

const { t, locale } = useI18n();
const { attachments, orientation } = useMessageContext();

const anexo = computed(() => props.anexo || attachments.value?.[0] || {});
const nome = computed(
  () => nomeDoArquivo(anexo.value) || t('CONVERSATION.UNKNOWN_FILE_TYPE')
);
const extensao = computed(() => extensaoDoArquivo(anexo.value).slice(0, 4));
const resumo = computed(() =>
  resumoDoArquivo(anexo.value, idiomaDoPainel(locale.value))
);
const ehPdf = computed(() => extensao.value === 'PDF');
// Foto mandada como documento: o app mostra a miniatura dela no lugar do ícone. O
// servidor só faz miniatura de anexo de imagem; o documento usa o próprio arquivo, só
// até 2 MB (acima disso, baixar o original para um quadrado de 78 px pesa demais).
// Se a imagem não carregar (link vencido), volta o ícone do tipo.
const IMAGENS = ['PNG', 'JPG', 'JPEG', 'WEBP', 'GIF'];
const ORIGINAL_MAX = 2 * 1024 * 1024;
const miniaturaFalhou = ref(false);
const fonteDaMiniatura = computed(() => {
  if (anexo.value.thumbUrl) return anexo.value.thumbUrl;
  return anexo.value.fileSize <= ORIGINAL_MAX ? anexo.value.dataUrl : null;
});
const miniatura = computed(() =>
  IMAGENS.includes(extensao.value) && !miniaturaFalhou.value
    ? fonteDaMiniatura.value
    : null
);
const enviada = computed(() => orientation?.value === 'right');

// PDF: a 1ª página que o servidor gera (thumbUrl). Se não carregar (PDF com senha,
// link vencido), fica o cartão sem prévia.
const previaFalhou = ref(false);
const previaDoPdf = computed(() =>
  ehPdf.value && !previaFalhou.value ? anexo.value.thumbUrl || null : null
);

const linkDeBaixar = computed(() => enderecoParaBaixar(anexo.value.dataUrl));
// Endereço de fora do Active Storage não vira download: abre noutra aba.
const deFora = computed(() => !doActiveStorage(anexo.value.dataUrl));
</script>

<template>
  <div
    class="flex flex-col w-full min-w-0 rounded-[8px] overflow-hidden"
    :class="
      enviada
        ? 'bg-[#D1F4CC] dark:bg-[#103E2A]'
        : 'bg-[#F5F5F5] dark:bg-[#1D1F1F]'
    "
    data-documento-do-whatsapp
  >
    <img
      v-if="previaDoPdf"
      :src="previaDoPdf"
      alt=""
      loading="lazy"
      class="w-full h-[150px] object-cover object-top bg-white skip-context-menu"
      data-previa-do-pdf
      @error="previaFalhou = true"
    />
    <div
      class="flex items-center gap-3 w-full min-w-0"
      :class="miniatura ? 'pe-3' : 'px-3 py-[13px]'"
    >
      <img
        v-if="miniatura"
        :src="miniatura"
        alt=""
        loading="lazy"
        class="size-[78px] flex-shrink-0 object-cover skip-context-menu"
        data-miniatura-do-documento
        @error="miniaturaFalhou = true"
      />
      <svg
        v-else
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
        :href="linkDeBaixar"
        :download="deFora ? undefined : nome"
        :target="deFora ? '_blank' : undefined"
        :rel="deFora ? 'noopener noreferrer' : undefined"
        class="grid place-content-center size-10 flex-shrink-0 rounded-full text-[#8C8C8C] dark:text-[#A7A8A8] hover:bg-[#000]/5 dark:hover:bg-white/5 skip-context-menu"
        :aria-label="t('CONVERSA_CANAL.MIDIA.BAIXAR', { nome })"
        data-baixar-documento
        @click.stop
      >
        <span class="i-ph-download-simple size-7" aria-hidden="true" />
      </a>
    </div>
  </div>
</template>
