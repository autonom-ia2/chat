<script setup>
import { ref, useId } from 'vue';
import { useI18n } from 'vue-i18n';
import LinhaDeColuna from './LinhaDeColuna.vue';

// #2894 — "O que vou guardar": cada coluna da planilha e para onde ela vai.
// Recolhido por padrão; abre com um clique.
defineProps({
  colunas: { type: Array, required: true },
  ocupado: { type: Boolean, default: false },
});
const emit = defineEmits(['trocar']);

const { t } = useI18n();
const id = useId();
const aberto = ref(false);
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
        :key="coluna.nome"
        :coluna="coluna"
        :ocupado="ocupado"
        @trocar="(nome, destino) => emit('trocar', nome, destino)"
      />
    </ul>
  </section>
</template>
