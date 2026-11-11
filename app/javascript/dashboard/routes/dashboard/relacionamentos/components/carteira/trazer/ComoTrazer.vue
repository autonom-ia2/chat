<script setup>
import { computed, useId } from 'vue';
import { useI18n } from 'vue-i18n';
import ErroComTentarDeNovo from '../../comum/ErroComTentarDeNovo.vue';
import { COMECO } from '../../../carteira/useTrazerSeguros';
import { COMO } from '../../../carteira/passosDeTrazerSeguros';

// #2897 — "Como você quer trazer seus clientes e seguros?": três cartões
// (planilha, PDFs das apólices, Agger). Cada cartão é um botão: clicar (ou
// Enter, ou Espaço) já leva ao passo daquele jeito. Não há "Continuar".
const props = defineProps({
  estado: { type: String, default: COMECO.PRONTO },
  aggerLigado: { type: Boolean, default: false },
});
const emit = defineEmits(['continuar', 'tentar']);

const { t } = useI18n();
const tc = chave => t(`RELACIONAMENTOS_CARTEIRA.TRAZER.COMO.${chave}`);
const id = useId();

const cartao = (como, icone, rotulo, descricao) => ({
  id: como,
  icone,
  rotulo: tc(rotulo),
  descricao: tc(descricao),
});
const opcoes = computed(() => [
  cartao(
    COMO.PLANILHA,
    'i-lucide-file-spreadsheet',
    'PLANILHA',
    'PLANILHA_APOIO'
  ),
  cartao(COMO.PDFS, 'i-lucide-file-text', 'PDFS', 'PDFS_APOIO'),
  cartao(
    COMO.AGGER,
    'i-lucide-link',
    'AGGER',
    props.aggerLigado ? 'AGGER_LIGADO' : 'AGGER_APOIO'
  ),
]);
</script>

<template>
  <section data-carteira="como-trazer" class="flex flex-col gap-8">
    <h1
      :id="`${id}-titulo`"
      data-titulo-da-tela
      tabindex="-1"
      class="m-0 text-3xl font-bold tracking-tight outline-none md:text-4xl text-n-slate-12"
    >
      {{ tc('TITULO') }}
    </h1>

    <div v-if="estado === COMECO.ERRO" data-carteira="erro">
      <ErroComTentarDeNovo :mensagem="tc('ERRO')" @tentar="emit('tentar')" />
    </div>
    <div
      v-else-if="estado === COMECO.CARREGANDO"
      data-carteira="carregando"
      role="status"
      aria-busy="true"
      :aria-label="t('RELACIONAMENTOS.COMUM.CARREGANDO')"
      class="grid gap-3 sm:grid-cols-3"
    >
      <div
        v-for="cartaoVazio in 3"
        :key="cartaoVazio"
        aria-hidden="true"
        class="h-28 rounded-2xl bg-n-slate-3 dark:bg-n-slate-5 animate-pulse"
      />
    </div>
    <div
      v-else
      role="group"
      data-carteira="cartoes-de-como"
      :aria-labelledby="`${id}-titulo`"
      class="grid gap-3 sm:grid-cols-3"
    >
      <button
        v-for="opcao in opcoes"
        :key="opcao.id"
        type="button"
        :data-carteira="`cartao-${opcao.id}`"
        class="flex items-start gap-4 px-5 py-4 transition-colors text-start min-h-28 rounded-2xl bg-n-solid-1 text-n-slate-12 ring-1 ring-inset ring-n-weak hover:bg-n-alpha-1 hover:ring-n-blue-9 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
        @click="emit('continuar', opcao.id)"
      >
        <span
          :data-icone="opcao.id"
          aria-hidden="true"
          class="inline-flex items-center justify-center size-11 shrink-0 rounded-xl bg-n-blue-3 text-n-blue-11"
        >
          <span class="size-6" :class="opcao.icone" />
        </span>
        <span data-texto-do-cartao class="flex flex-col min-w-0 gap-1">
          <span class="text-lg font-semibold">{{ opcao.rotulo }}</span>
          <span class="text-base text-n-slate-11">{{ opcao.descricao }}</span>
        </span>
      </button>
    </div>
  </section>
</template>
