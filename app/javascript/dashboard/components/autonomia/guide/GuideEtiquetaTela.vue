<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';

// #934 — "Vendo: 12 cards selecionados", logo acima da caixa de texto. Diz o que
// o Guia vai levar junto da pergunta; o × manda a próxima sem isso.
// Só aparece com algo aberto ou selecionado: filtro sozinho viaja calado.
const props = defineProps({
  // O objeto `tela` de `contextoAtual`.
  tela: { type: Object, default: () => ({}) },
  // A pessoa tirou a etiqueta: a próxima pergunta vai sem a tela.
  oculta: { type: Boolean, default: false },
});

const emit = defineEmits(['remover']);
const { t } = useI18n();

const NOMES = {
  'crm/cards': 'CARDS',
  conversations: 'CONVERSAS',
  contacts: 'CONTATOS',
};
const nome = recurso => NOMES[recurso] || 'OUTROS';

const texto = computed(() => {
  if (props.oculta) return '';
  const { selecionados, aberto } = props.tela || {};
  if (selecionados?.total) {
    return t(
      `AUTONOMIA_GUIDE.TELA.SELECTED.${nome(selecionados.recurso)}`,
      { count: selecionados.total },
      selecionados.total
    );
  }
  if (aberto?.length) {
    return t(`AUTONOMIA_GUIDE.TELA.OPEN.${nome(aberto[0].recurso)}`);
  }
  return '';
});

const anuncio = ref('');
// A etiqueta voltou: o aviso de que ela saiu não vale mais.
watch(
  () => props.oculta,
  oculta => {
    if (!oculta) anuncio.value = '';
  }
);

const remover = () => {
  anuncio.value = t('AUTONOMIA_GUIDE.TELA.REMOVED');
  emit('remover');
};
</script>

<template>
  <div>
    <div
      v-if="texto"
      data-etiqueta-tela
      class="flex items-center gap-2 max-w-full rounded-lg border border-n-weak bg-n-alpha-1 ltr:pl-3 rtl:pr-3 mb-2 text-sm"
    >
      <span
        class="i-lucide-eye size-4 shrink-0 text-n-slate-11"
        aria-hidden="true"
      />
      <span class="truncate min-w-0 flex-1 text-n-slate-12" role="status">
        {{ texto }}
      </span>
      <button
        type="button"
        data-etiqueta-tela-remover
        :aria-label="$t('AUTONOMIA_GUIDE.TELA.REMOVE')"
        :title="$t('AUTONOMIA_GUIDE.TELA.REMOVE')"
        class="h-11 w-11 shrink-0 flex items-center justify-center rounded-lg text-n-slate-11 hover:text-n-ruby-11 focus-visible:outline-2 focus-visible:outline focus-visible:outline-n-blue-11"
        @click="remover"
      >
        <i class="i-lucide-x" aria-hidden="true" />
      </button>
    </div>
    <p class="sr-only" role="status" aria-live="polite">{{ anuncio }}</p>
  </div>
</template>
