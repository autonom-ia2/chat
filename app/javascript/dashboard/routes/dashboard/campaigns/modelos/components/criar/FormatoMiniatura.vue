<script setup>
import { CODIGO_DE_EXEMPLO } from '../../constants';

// Prévia mínima de cada formato no cartão de escolha: um desenho do jeito que
// a mensagem chega, sem texto de verdade.
defineProps({
  formato: { type: String, required: true },
});
</script>

<template>
  <span
    aria-hidden="true"
    class="flex flex-col justify-end w-full gap-1 p-2.5 rounded-xl h-[5.5rem] bg-n-slate-3"
  >
    <template v-if="formato === 'carrossel'">
      <span class="w-3/5 h-2 rounded bg-n-solid-1" />
      <span class="flex gap-1">
        <span
          v-for="n in 3"
          :key="n"
          class="flex flex-col w-1/3 overflow-hidden rounded bg-n-solid-1"
        >
          <span class="h-6 bg-n-blue-4" />
          <span class="h-1.5 m-1 rounded bg-n-slate-5" />
        </span>
      </span>
    </template>
    <template v-else-if="formato === 'oferta'">
      <span class="flex items-center gap-1 p-1 rounded bg-n-solid-1">
        <span class="i-lucide-timer size-3.5 text-n-ruby-11" />
        <span class="w-10 h-1.5 rounded bg-n-ruby-5" />
      </span>
      <span class="w-4/5 h-2 rounded bg-n-solid-1" />
      <span class="w-1/2 h-4 rounded bg-n-solid-1" />
    </template>
    <template v-else-if="formato === 'produtos'">
      <span class="flex gap-1">
        <span
          v-for="n in 2"
          :key="n"
          class="flex flex-col w-1/2 overflow-hidden rounded bg-n-solid-1"
        >
          <span class="grid h-7 place-items-center bg-n-teal-4">
            <span class="i-lucide-shopping-cart size-3.5 text-n-teal-11" />
          </span>
          <span class="h-1.5 m-1 rounded bg-n-slate-5" />
        </span>
      </span>
      <span class="w-3/4 h-2 rounded bg-n-solid-1" />
    </template>
    <template v-else-if="formato === 'catalogo'">
      <span class="grid h-8 rounded place-items-center bg-n-solid-1">
        <span class="i-lucide-shopping-bag size-4 text-n-teal-11" />
      </span>
      <span class="w-3/4 h-2 rounded bg-n-solid-1" />
      <span class="grid w-3/5 h-4 rounded place-items-center bg-n-solid-1">
        <span class="w-8 h-1.5 rounded bg-n-blue-5" />
      </span>
    </template>
    <template v-else-if="formato === 'codigo'">
      <span class="flex items-center gap-1 p-1 rounded bg-n-solid-1">
        <span
          class="px-1 text-[0.625rem] font-bold rounded bg-n-amber-3 text-n-slate-12"
        >
          <span>{{ CODIGO_DE_EXEMPLO }}</span>
        </span>
        <span class="w-12 h-1.5 rounded bg-n-slate-5" />
      </span>
      <span class="grid w-3/5 h-4 rounded place-items-center bg-n-solid-1">
        <span class="i-lucide-copy size-3 text-n-blue-11" />
      </span>
    </template>
    <template v-else>
      <span class="w-4/5 h-2 rounded bg-n-solid-1" />
      <span class="flex flex-col gap-1 p-1.5 rounded bg-n-solid-1">
        <span class="w-full h-1.5 rounded bg-n-slate-5" />
        <span class="w-2/3 h-1.5 rounded bg-n-slate-5" />
      </span>
      <span class="grid w-3/5 h-4 rounded place-items-center bg-n-solid-1">
        <span class="i-lucide-clipboard-list size-3 text-n-blue-11" />
      </span>
    </template>
  </span>
</template>
