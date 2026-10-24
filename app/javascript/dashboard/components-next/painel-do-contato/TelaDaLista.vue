<script setup>
// #2138 — o conteúdo de uma linha que abre, no lugar do painel, com "Voltar" no alto.
// Cada item é uma frase; tocar numa conversa anterior abre essa conversa (no celular,
// o painel fecha junto, para a conversa aparecer).
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useWindowSize } from '@vueuse/core';
import { useUISettings } from 'dashboard/composables/useUISettings';
import { useConversationRoutePath } from 'dashboard/composables/useConversationRoutePath';
import wootConstants from 'dashboard/constants/globals';
import Button from 'dashboard/components-next/button/Button.vue';
import InformacoesDoContato from './InformacoesDoContato.vue';
import { useDataFalada } from './useDataFalada';
import { nomeDoArquivo } from './nomeDoArquivo';

const props = defineProps({
  tipo: { type: String, required: true },
  listas: { type: Object, required: true },
  contact: { type: Object, required: true },
  podeEditar: { type: Boolean, default: false },
});
const emit = defineEmits(['voltar']);

const { t } = useI18n();
const router = useRouter();
const { buildConversationPath } = useConversationRoutePath();
const { updateUISettings } = useUISettings();
const { width } = useWindowSize();
const { dia } = useDataFalada();

const TITULOS = {
  conversas: () => t('PAINEL_DO_CONTATO.LISTAS.TITULO_CONVERSAS'),
  arquivos: () => t('PAINEL_DO_CONTATO.LISTAS.TITULO_ARQUIVOS'),
  informacoes: () => t('PAINEL_DO_CONTATO.LISTAS.TITULO_INFORMACOES'),
  acompanham: () => t('PAINEL_DO_CONTATO.LISTAS.TITULO_ACOMPANHAM'),
};
const titulo = computed(() => TITULOS[props.tipo]?.() || '');

const fraseDaConversa = conversa => {
  const quando = conversa.last_activity_at || conversa.created_at;
  const diaFalado = dia(new Date(quando * 1000));
  const dono = conversa.meta?.assignee;
  const ia = dono && (conversa.meta?.assignee_type || 'User') !== 'User';
  let frase;
  if (!dono)
    frase = t('PAINEL_DO_CONTATO.LISTAS.CONVERSA_SEM_NINGUEM', {
      dia: diaFalado,
    });
  else if (ia)
    frase = t('PAINEL_DO_CONTATO.LISTAS.CONVERSA_COM_IA', {
      dia: diaFalado,
      nome: dono.name,
    });
  else
    frase = t('PAINEL_DO_CONTATO.LISTAS.CONVERSA_COM', {
      dia: diaFalado,
      nome: dono.name,
    });
  return conversa.status === 'open'
    ? `${frase} ${t('PAINEL_DO_CONTATO.LISTAS.AINDA_ABERTA')}`
    : frase;
};

const abrirConversa = conversa => {
  const caminho = buildConversationPath(conversa.id);
  if (!caminho) return;
  if (width.value < wootConstants.SMALL_SCREEN_BREAKPOINT) {
    updateUISettings({ is_contact_sidebar_open: false });
  }
  router.push({ path: caminho });
};

const ehImagem = anexo => anexo.file_type === 'image';
const abrirArquivo = anexo =>
  window.open(anexo.data_url, '_blank', 'noopener,noreferrer');
</script>

<template>
  <div class="flex flex-col">
    <div class="flex items-center gap-1 px-2 border-b border-n-weak min-h-12">
      <Button
        :label="t('PAINEL_DO_CONTATO.VOLTAR')"
        icon="i-lucide-arrow-left"
        variant="ghost"
        color="slate"
        size="sm"
        class="min-h-11"
        @click="emit('voltar')"
      />
    </div>
    <h3 class="px-4 pt-4 pb-2 m-0 text-base font-semibold text-n-slate-12">
      {{ titulo }}
    </h3>

    <ul
      v-if="tipo === 'conversas'"
      class="flex flex-col px-2 pb-4 m-0 list-none"
    >
      <li v-for="conversa in listas.conversas" :key="conversa.id">
        <button
          type="button"
          class="flex items-center w-full gap-2 px-2 py-2 text-sm text-left rounded-lg min-h-11 text-n-slate-12 hover:bg-n-alpha-2"
          @click="abrirConversa(conversa)"
        >
          <span class="flex-1 min-w-0">{{ fraseDaConversa(conversa) }}</span>
          <span
            class="flex-shrink-0 i-lucide-chevron-right size-4 text-n-slate-11"
          />
        </button>
      </li>
    </ul>

    <ul
      v-else-if="tipo === 'arquivos'"
      class="flex flex-col px-2 pb-4 m-0 list-none"
    >
      <li v-for="anexo in listas.arquivos" :key="anexo.id">
        <button
          type="button"
          class="flex items-center w-full gap-3 px-2 py-1 text-sm text-left rounded-lg min-h-11 text-n-slate-12 hover:bg-n-alpha-2"
          :aria-label="
            t('PAINEL_DO_CONTATO.LISTAS.ABRIR_ARQUIVO', {
              nome: nomeDoArquivo(anexo),
            })
          "
          @click="abrirArquivo(anexo)"
        >
          <img
            v-if="ehImagem(anexo)"
            :src="anexo.data_url"
            alt=""
            class="object-cover rounded-md size-10 bg-n-alpha-2"
          />
          <span
            v-else
            class="flex items-center justify-center flex-shrink-0 rounded-md size-10 bg-n-alpha-2"
          >
            <span class="i-lucide-file-text size-5 text-n-slate-11" />
          </span>
          <span class="flex-1 min-w-0 truncate">{{
            nomeDoArquivo(anexo)
          }}</span>
        </button>
      </li>
    </ul>

    <InformacoesDoContato
      v-else-if="tipo === 'informacoes'"
      :definicoes="listas.informacoes"
      :contact="contact"
      :pode-editar="podeEditar"
    />

    <div
      v-else-if="tipo === 'acompanham'"
      class="flex flex-col gap-3 px-4 pb-4"
    >
      <ul class="flex flex-col gap-2 p-0 m-0 list-none">
        <li
          v-for="pessoa in listas.quemAcompanha"
          :key="pessoa.id"
          class="text-sm text-n-slate-12"
        >
          {{ pessoa.name }}
        </li>
      </ul>
      <p class="m-0 text-sm text-n-slate-12">
        {{ t('PAINEL_DO_CONTATO.LISTAS.ACOMPANHAR_NO_MENU') }}
      </p>
    </div>
  </div>
</template>
