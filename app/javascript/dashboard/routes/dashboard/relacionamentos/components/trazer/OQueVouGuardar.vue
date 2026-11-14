<script setup>
import { ref, useId } from 'vue';
import { useI18n } from 'vue-i18n';
import LinhaDeColuna from './LinhaDeColuna.vue';
import { chaveDaColuna } from '../../trazer/destinos';

// #2894 — "O que vou guardar": cada coluna da planilha e para onde ela vai.
// Recolhido por padrão; abre com um clique.
// Fatia 2 — `recusa` (`{ coluna, chave }`): a troca que não deu certo é dita na
// linha da coluna dela. `relendo`: a planilha está sendo lida de novo.
const props = defineProps({
  colunas: { type: Array, required: true },
  ocupado: { type: Boolean, default: false },
  relendo: { type: Boolean, default: false },
  recusa: { type: Object, default: null },
  // #2896 — se o telefone da empresa existe nesta leitura.
  temEmpresa: { type: Boolean, default: true },
  // #2897 — destinos que só existem em quem usa (os de seguro): `{ value, label }`.
  destinosAMais: { type: Array, default: () => [] },
  // #2897 — a tela que pede para a pessoa mexer nas colunas já as mostra.
  comecaAberto: { type: Boolean, default: false },
});
const emit = defineEmits(['trocar']);

const { t } = useI18n();
const id = useId();
const aberto = ref(props.comecaAberto);
</script>

<template>
  <section data-relacionamentos="o-que-vou-guardar" class="flex flex-col gap-2">
    <h2 class="m-0 text-2xl font-semibold tracking-tight text-n-slate-12">
      <button
        type="button"
        class="flex items-center gap-2 p-0 text-2xl font-semibold tracking-tight bg-transparent border-0 text-start min-h-11 rounded-lg focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
        :aria-expanded="aberto ? 'true' : 'false'"
        :aria-controls="`${id}-colunas`"
        @click="aberto = !aberto"
      >
        {{ t('RELACIONAMENTOS_TRAZER.GUARDAR.TITULO') }}
        <span
          class="i-lucide-chevron-down size-5 text-n-slate-10 transition-transform"
          :class="{ 'rotate-180': aberto }"
          aria-hidden="true"
        />
      </button>
    </h2>
    <p
      v-show="!aberto"
      data-relacionamentos="guardar-apoio"
      class="m-0 text-base text-n-slate-11"
    >
      {{ t('RELACIONAMENTOS_TRAZER.GUARDAR.APOIO') }}
    </p>
    <ul
      v-show="aberto"
      :id="`${id}-colunas`"
      class="p-0 m-0 list-none divide-y divide-n-weak"
    >
      <LinhaDeColuna
        v-for="coluna in colunas"
        :key="chaveDaColuna(coluna)"
        :coluna="coluna"
        :ocupado="ocupado"
        :relendo="relendo"
        :recusa="recusa?.coluna === chaveDaColuna(coluna) ? recusa : null"
        :tem-empresa="temEmpresa"
        :destinos-a-mais="destinosAMais"
        @trocar="(...troca) => emit('trocar', ...troca)"
      />
    </ul>
  </section>
</template>
