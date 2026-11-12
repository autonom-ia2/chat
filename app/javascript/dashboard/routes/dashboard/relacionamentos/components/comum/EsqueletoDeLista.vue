<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

// #2894 — "carregando" das listas, no formato da tela que vem: blocos cinzas
// que pulsam, uma linha "Carregando…" visível e, para o leitor de tela, o mesmo
// texto uma vez só (o visível é `aria-hidden`).
// `comTopo` desenha também o bloco alto do topo escuro e a fileira de grupos
// (carregamento da página inteira); sem ele, só as linhas (lista, ficha).
defineProps({
  linhas: { type: Number, default: 6 },
  comTopo: { type: Boolean, default: false },
});

const GRUPOS_NA_FILEIRA = 5;

const { t } = useI18n();
const textoVisivel = computed(
  () => `${t('RELACIONAMENTOS.COMUM.CARREGANDO')}…`
);
</script>

<template>
  <div
    data-esqueleto
    role="status"
    aria-busy="true"
    class="flex flex-col gap-3"
  >
    <span class="sr-only">{{ t('RELACIONAMENTOS.COMUM.CARREGANDO') }}</span>
    <p aria-hidden="true" class="m-0 text-sm text-n-slate-11">
      {{ textoVisivel }}
    </p>
    <template v-if="comTopo">
      <div
        data-esqueleto-topo
        aria-hidden="true"
        class="h-48 mb-3 rounded-3xl bg-n-slate-3 dark:bg-n-slate-5 animate-pulse motion-reduce:animate-none md:h-56"
      />
      <div
        data-esqueleto-grupos
        aria-hidden="true"
        class="flex gap-2 mb-3 overflow-hidden animate-pulse motion-reduce:animate-none"
      >
        <span
          v-for="grupo in GRUPOS_NA_FILEIRA"
          :key="grupo"
          class="h-11 rounded-full w-28 shrink-0 bg-n-slate-3 dark:bg-n-slate-5"
        />
      </div>
    </template>
    <div
      v-for="linha in linhas"
      :key="linha"
      data-esqueleto-linha
      aria-hidden="true"
      class="flex items-center h-16 gap-4 px-2 animate-pulse motion-reduce:animate-none"
    >
      <span
        class="rounded-full size-10 shrink-0 bg-n-slate-3 dark:bg-n-slate-5"
      />
      <span class="flex flex-col flex-1 min-w-0 gap-2">
        <span class="w-1/2 h-3.5 rounded-md bg-n-slate-3 dark:bg-n-slate-5" />
        <span class="w-1/3 h-3 rounded-md bg-n-slate-3 dark:bg-n-slate-5" />
      </span>
    </div>
  </div>
</template>
