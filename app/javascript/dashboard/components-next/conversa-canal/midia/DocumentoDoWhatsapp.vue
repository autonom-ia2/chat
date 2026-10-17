<script setup>
// Documento no balão com a cara do WhatsApp (#1702): o cartão do app, com o ícone do
// tipo (PDF em vermelho), o nome, "PDF • 107 KB" e o botão de baixar à direita, que
// salva o arquivo com o nome dele (o link direto abria o arquivo noutra aba).
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useMessageContext } from '../../message/provider.js';
import { idiomaDoPainel } from '../dataDaConversa';
import {
  extensaoDoArquivo,
  nomeDoArquivo,
  resumoDoArquivo,
} from './tamanhoDoArquivo';
import { baixarArquivo } from './baixarArquivo';

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
// Foto mandada como documento: o app mostra a miniatura dela no lugar do ícone.
const IMAGENS = ['PNG', 'JPG', 'JPEG', 'WEBP', 'GIF'];
const miniatura = computed(() =>
  IMAGENS.includes(extensao.value)
    ? anexo.value.thumbUrl || anexo.value.dataUrl
    : null
);
const enviada = computed(() => orientation?.value === 'right');

const baixando = ref(false);
const baixar = async () => {
  if (baixando.value) return;
  baixando.value = true;
  try {
    await baixarArquivo({ url: anexo.value.dataUrl, nome: nome.value });
  } catch {
    useAlert(t('GALLERY_VIEW.ERROR_DOWNLOADING'));
  } finally {
    baixando.value = false;
  }
};
</script>

<template>
  <div
    class="flex items-center gap-3 w-full min-w-0 rounded-[8px] overflow-hidden"
    :class="[
      enviada
        ? 'bg-[#D1F4CC] dark:bg-[#103E2A]'
        : 'bg-[#F5F5F5] dark:bg-[#1D1F1F]',
      miniatura ? 'pe-3' : 'px-3 py-[13px]',
    ]"
    data-documento-do-whatsapp
  >
    <img
      v-if="miniatura"
      :src="miniatura"
      alt=""
      class="size-[78px] flex-shrink-0 object-cover skip-context-menu"
      data-miniatura-do-documento
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
    <button
      v-if="anexo.dataUrl"
      type="button"
      class="grid place-content-center size-10 flex-shrink-0 rounded-full text-[#8C8C8C] dark:text-[#A7A8A8] hover:bg-[#000]/5 dark:hover:bg-white/5 disabled:opacity-50 skip-context-menu"
      :aria-label="t('CONVERSA_CANAL.MIDIA.BAIXAR', { nome })"
      :disabled="baixando"
      :aria-busy="baixando"
      data-baixar-documento
      @click.stop="baixar"
    >
      <span
        :class="baixando ? 'i-ph-spinner animate-spin' : 'i-ph-download-simple'"
        class="size-7"
        aria-hidden="true"
      />
    </button>
  </div>
</template>
