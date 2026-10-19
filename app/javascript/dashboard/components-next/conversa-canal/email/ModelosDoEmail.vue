<script setup>
// Respostas prontas na resposta de e-mail (#1786): o botão abre a mesma lista do "/"
// (busca, prévia formatada), mas sem escrever "/" no texto. Escolher manda o conteúdo
// ao ReplyBox, que troca as variáveis e põe no ponto do cursor, com a formatação.
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { picoSearch } from '@chatwoot/pico-search';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useMessageFormatter } from 'shared/composables/useMessageFormatter';
import CaretAnchoredPicker from 'dashboard/components-next/preview-picker/CaretAnchoredPicker.vue';
import Icon from 'next/icon/Icon.vue';
import { emitter } from 'shared/helpers/mitt';
import { MODELOS_DO_EMAIL } from './useConversaDeEmail';

const ALTURA_DO_BOTAO = 40;

const { t } = useI18n();
const store = useStore();
const { getPlainText, formatMessage } = useMessageFormatter();
const respostas = useMapGetter('getCannedResponses');
const uiFlags = useMapGetter('getUIFlags');

const aberto = ref(false);
const busca = ref('');

const registros = computed(() =>
  respostas.value.map(({ id, short_code: atalho, content }) => ({
    id,
    content,
    atalho,
    texto: getPlainText(content).split('\n').join(' ').trim(),
  }))
);

const itens = computed(() => {
  const termo = busca.value.trim();
  const achados = termo
    ? picoSearch(registros.value, termo, [
        { name: 'atalho', weight: 1 },
        'texto',
      ])
    : registros.value;
  return achados.map(r => ({
    id: r.id,
    content: r.content,
    label: r.atalho,
    title: r.atalho,
    subtitle: r.texto,
  }));
});

const abrir = () => {
  if (aberto.value) return;
  busca.value = '';
  aberto.value = true;
  store.dispatch('getCannedResponse');
};

const escolher = item => {
  aberto.value = false;
  emitter.emit(MODELOS_DO_EMAIL, item.content);
};
</script>

<template>
  <div class="relative">
    <button
      type="button"
      :aria-label="t('CONVERSA_CANAL.EMAIL.MODELOS')"
      :title="t('CONVERSA_CANAL.EMAIL.MODELOS')"
      :aria-expanded="aberto"
      data-modelos-do-email
      @click="abrir"
    >
      <Icon icon="i-lucide-file-text" class="size-[22px]" />
    </button>
    <div
      v-if="aberto"
      class="absolute start-0 bottom-0 w-[42rem] max-w-[calc(100vw-2rem)] pointer-events-none"
      :style="{ height: `${ALTURA_DO_BOTAO}px` }"
    >
      <CaretAnchoredPicker
        v-model:search="busca"
        :caret-position="{ top: 0, height: ALTURA_DO_BOTAO }"
        :items="itens"
        :search-placeholder="t('CONVERSA_CANAL.EMAIL.BUSCAR_MODELO')"
        :is-loading="uiFlags.fetchingList"
        :empty-label="
          busca.trim()
            ? t('COMBOBOX.EMPTY_SEARCH_RESULTS', { searchTerm: busca.trim() })
            : t('CONVERSA_CANAL.EMAIL.SEM_MODELOS')
        "
        data-lista-de-modelos
        @select="escolher"
        @close="aberto = false"
        @remove-trigger="aberto = false"
      >
        <template #preview="{ item }">
          <div
            v-dompurify-html="formatMessage(item?.content || '')"
            class="px-4 py-3 prose prose-bubble !max-w-none prose-a:text-n-brand"
          />
        </template>
      </CaretAnchoredPicker>
    </div>
  </div>
</template>
