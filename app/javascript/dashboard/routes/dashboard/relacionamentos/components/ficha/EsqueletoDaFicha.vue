<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

// #2894 — "carregando" da ficha: a forma dela em cinza que pulsa (cabeçalho com
// círculo e barras, e dois cartões por coluna). O leitor de tela ouve "Carregando"
// pela região viva da página (`AvisoVivo`), que não nasce junto com o esqueleto:
// por isso o texto visível é `aria-hidden`, para não anunciar duas vezes.
const { t } = useI18n();
const texto = computed(() => `${t('RELACIONAMENTOS.COMUM.CARREGANDO')}…`);
const BLOCO = 'bg-n-alpha-2 animate-pulse motion-reduce:animate-none';
</script>

<template>
  <div
    data-relacionamentos="carregando"
    aria-busy="true"
    class="flex flex-col gap-6"
  >
    <p
      data-relacionamentos="carregando-texto"
      aria-hidden="true"
      class="m-0 text-base text-n-slate-11"
    >
      {{ texto }}
    </p>
    <div
      aria-hidden="true"
      class="flex items-center gap-4 p-5 border rounded-2xl border-n-weak bg-n-solid-1 md:p-8"
    >
      <div
        data-bloco="circulo"
        class="rounded-full size-16 shrink-0 md:size-20"
        :class="BLOCO"
      />
      <div class="flex flex-col flex-1 min-w-0 gap-3">
        <div data-bloco="barra" class="w-2/3 h-6 rounded-lg" :class="BLOCO" />
        <div data-bloco="barra" class="w-1/2 h-4 rounded-lg" :class="BLOCO" />
        <div data-bloco="barra" class="w-1/3 h-4 rounded-lg" :class="BLOCO" />
      </div>
    </div>
    <div aria-hidden="true" class="grid gap-6 lg:grid-cols-3">
      <div
        data-bloco="cartao"
        class="h-56 rounded-2xl lg:col-span-2"
        :class="BLOCO"
      />
      <div data-bloco="cartao" class="h-56 rounded-2xl" :class="BLOCO" />
    </div>
  </div>
</template>
