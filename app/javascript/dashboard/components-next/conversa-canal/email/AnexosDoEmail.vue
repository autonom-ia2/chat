<script setup>
// Anexos de um e-mail (#1786), como no Gmail: uma faixa "3 anexos · 2,4 MB" e cartões
// do mesmo tamanho. Foto mostra a miniatura e abre na galeria do painel (com as outras
// fotos da conversa); arquivo mostra a cor e a sigla do tipo (PDF, planilha, texto,
// compactado), o nome inteiro ao passar o mouse, a sigla e o tamanho. Tocar abre; o
// botão redondo baixa. Sem miniatura (servidor sem processador de imagem), a foto usa o
// arquivo original; sem ele também, vira cartão de arquivo.
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { getFileInfo } from '@chatwoot/utils';
import Icon from 'next/icon/Icon.vue';
import FileIcon from 'next/icon/FileIcon.vue';
import GalleryView from 'dashboard/components/widgets/conversation/components/GalleryView.vue';
import { useSnakeCase } from 'dashboard/composables/useTransformKeys';
import { useMessageContext } from '../../message/provider.js';
import { ATTACHMENT_TYPES } from '../../message/constants.js';
import { idiomaDoPainel } from '../dataDaConversa';

const props = defineProps({
  anexos: { type: Array, required: true },
});

const { t, locale } = useI18n();
const { filteredCurrentChatAttachments } = useMessageContext();

// Cor do cartão por família de arquivo (tokens do design system, valem no escuro).
const FAMILIAS = {
  pdf: { cor: 'bg-n-ruby-3 text-n-ruby-11', sigla: 'PDF' },
  planilha: { cor: 'bg-n-teal-3 text-n-teal-11', sigla: 'XLS' },
  texto: { cor: 'bg-n-blue-3 text-n-blue-11', sigla: 'DOC' },
  slides: { cor: 'bg-n-amber-3 text-n-amber-11', sigla: 'PPT' },
  pacote: { cor: 'bg-n-slate-3 text-n-slate-11', sigla: 'ZIP' },
  midia: { cor: 'bg-n-iris-3 text-n-iris-11', sigla: '' },
  outro: { cor: 'bg-n-slate-3 text-n-slate-11', sigla: '' },
};
const FAMILIA_DO_TIPO = {
  pdf: 'pdf',
  xls: 'planilha',
  xlsx: 'planilha',
  csv: 'planilha',
  ods: 'planilha',
  doc: 'texto',
  docx: 'texto',
  odt: 'texto',
  rtf: 'texto',
  txt: 'texto',
  ppt: 'slides',
  pptx: 'slides',
  key: 'slides',
  zip: 'pacote',
  rar: 'pacote',
  '7z': 'pacote',
  tar: 'pacote',
  gz: 'pacote',
};

const UM_KB = 1024;
const UM_MB = UM_KB * 1024;
const tamanho = bytes => {
  if (!bytes) return '';
  // "pt_BR" do painel vira "pt-BR" (o Intl recusa o sublinhado).
  const numero = new Intl.NumberFormat(idiomaDoPainel(locale.value), {
    maximumFractionDigits: bytes >= UM_MB ? 1 : 0,
  });
  return bytes >= UM_MB
    ? `${numero.format(bytes / UM_MB)} MB`
    : `${numero.format(Math.max(1, bytes / UM_KB))} KB`;
};

const itens = computed(() =>
  props.anexos.map(anexo => {
    const { name, type } = getFileInfo(anexo.dataUrl || '');
    const tipo = String(type || anexo.extension || '').toLowerCase();
    const ehFoto = anexo.fileType === ATTACHMENT_TYPES.IMAGE;
    const ehMidia = [ATTACHMENT_TYPES.VIDEO, ATTACHMENT_TYPES.AUDIO].includes(
      anexo.fileType
    );
    const familia =
      FAMILIAS[ehMidia ? 'midia' : FAMILIA_DO_TIPO[tipo] || 'outro'];
    return {
      anexo,
      ehFoto,
      nome: decodeURIComponent(name || ''),
      tipo,
      sigla: familia.sigla || tipo.toUpperCase().slice(0, 4),
      cor: familia.cor,
      tamanho: tamanho(anexo.fileSize),
    };
  })
);

const total = computed(() =>
  tamanho(props.anexos.reduce((soma, a) => soma + (a.fileSize || 0), 0))
);

const naGaleria = ref(null);
// 0 = miniatura, 1 = arquivo original, 2 = mostrar como arquivo.
const tentativa = ref({});
const fonteDaFoto = anexo =>
  (tentativa.value[anexo.id] || 0) === 0
    ? anexo.thumbUrl || anexo.dataUrl
    : anexo.dataUrl;
const falhouFoto = anexo => {
  tentativa.value = {
    ...tentativa.value,
    [anexo.id]: (tentativa.value[anexo.id] || 0) + 1,
  };
};
const comoFoto = item =>
  item.ehFoto && (tentativa.value[item.anexo.id] || 0) < 2;
</script>

<template>
  <div class="mt-5 pt-4 border-t border-n-weak" data-anexos-do-email>
    <p class="flex items-center gap-1.5 mb-3 text-xs text-n-slate-11">
      <Icon icon="i-lucide-paperclip" class="size-3.5" />
      <span class="font-medium text-n-slate-12">
        {{
          t(
            'CONVERSA_CANAL.EMAIL.ANEXOS',
            { total: anexos.length },
            anexos.length
          )
        }}
      </span>
      <span v-if="total" aria-hidden="true">·</span>
      <span v-if="total" class="tabular-nums">{{ total }}</span>
    </p>
    <ul
      class="reset-base list-none grid grid-cols-2 sm:grid-cols-[repeat(auto-fill,minmax(10rem,1fr))] gap-2.5 max-w-[44rem]"
    >
      <li
        v-for="item in itens"
        :key="item.anexo.id"
        class="list-none group relative flex flex-col min-w-0 overflow-hidden rounded-xl border border-n-weak bg-n-surface-1 transition-shadow hover:shadow-[0_1px_3px_rgba(0,0,0,0.12),0_4px_12px_rgba(0,0,0,0.08)] focus-within:shadow-[0_1px_3px_rgba(0,0,0,0.12),0_4px_12px_rgba(0,0,0,0.08)]"
        :data-anexo="item.ehFoto ? 'foto' : item.tipo || 'arquivo'"
      >
        <button
          v-if="comoFoto(item)"
          type="button"
          class="block aspect-[16/10] w-full overflow-hidden bg-n-alpha-1 focus-visible:outline focus-visible:outline-2 focus-visible:-outline-offset-2 focus-visible:outline-n-brand"
          :aria-label="
            t('CONVERSA_CANAL.EMAIL.ABRIR_ANEXO', { nome: item.nome })
          "
          @click="naGaleria = item.anexo"
        >
          <img
            :src="fonteDaFoto(item.anexo)"
            :alt="item.nome"
            loading="lazy"
            class="size-full object-cover transition-transform duration-300 group-hover:scale-[1.03] skip-context-menu"
            @error="falhouFoto(item.anexo)"
          />
        </button>
        <a
          v-else
          :href="item.anexo.dataUrl"
          target="_blank"
          rel="noopener noreferrer"
          class="grid place-content-center aspect-[16/10] w-full focus-visible:outline focus-visible:outline-2 focus-visible:-outline-offset-2 focus-visible:outline-n-brand"
          :class="item.cor"
          :aria-label="
            t('CONVERSA_CANAL.EMAIL.ABRIR_ANEXO', { nome: item.nome })
          "
        >
          <FileIcon :file-type="item.tipo" class="size-9" />
        </a>
        <div class="flex items-center gap-1 min-w-0 ps-3 pe-1 py-1.5">
          <div class="flex-1 min-w-0">
            <p
              class="line-clamp-2 break-all text-[13px] leading-[18px] font-medium text-n-slate-12"
              :title="item.nome"
            >
              {{ item.nome }}
            </p>
            <p class="text-xs text-n-slate-11 tabular-nums">
              {{ [item.sigla, item.tamanho].filter(Boolean).join(' · ') }}
            </p>
          </div>
          <a
            :href="item.anexo.dataUrl"
            download
            class="grid place-content-center flex-shrink-0 size-9 rounded-full text-n-slate-11 hover:bg-n-alpha-2 hover:text-n-slate-12 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
            :aria-label="
              t('CONVERSA_CANAL.EMAIL.BAIXAR_ANEXO', { nome: item.nome })
            "
            :title="t('CONVERSA_CANAL.EMAIL.BAIXAR')"
            data-baixar-anexo
          >
            <Icon icon="i-lucide-download" class="size-4" />
          </a>
        </div>
      </li>
    </ul>
    <GalleryView
      v-if="naGaleria"
      :show="Boolean(naGaleria)"
      :attachment="useSnakeCase(naGaleria)"
      :all-attachments="filteredCurrentChatAttachments"
      @close="naGaleria = null"
      @update:show="valor => !valor && (naGaleria = null)"
    />
  </div>
</template>
