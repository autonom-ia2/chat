<script setup>
import { MODELOS } from '../modelos';

// #982 — as automações prontas em cartões grandes: ícone, título, para que
// serve e as linhas "Quando" e "Faz". O cartão inteiro é o botão.
defineProps({
  desabilitado: { type: Boolean, default: false },
});

const emit = defineEmits(['escolher']);
</script>

<template>
  <ul
    class="grid list-none gap-5 p-0 m-0 grid-cols-[repeat(auto-fit,minmax(min(100%,18rem),1fr))]"
  >
    <li v-for="modelo in MODELOS" :key="modelo.chave" class="flex">
      <button
        type="button"
        :data-modelo="modelo.chave"
        :disabled="desabilitado"
        class="group flex flex-col w-full gap-4 p-6 text-start rounded-2xl ring-1 ring-inset ring-n-weak bg-n-solid-1 shadow-sm transition hover:-translate-y-0.5 hover:shadow-lg hover:ring-n-blue-7 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand disabled:cursor-not-allowed disabled:opacity-60 disabled:hover:translate-y-0 disabled:hover:shadow-sm"
        @click="emit('escolher', modelo.chave)"
      >
        <span class="flex items-center justify-between w-full">
          <span
            class="grid place-items-center size-14 rounded-2xl"
            :class="modelo.tom"
          >
            <span class="size-7" :class="modelo.icone" aria-hidden="true" />
          </span>
          <span
            class="inline-flex items-center gap-1.5 text-sm font-medium text-n-blue-11 opacity-80 group-hover:opacity-100"
          >
            {{ $t('AUTOMACOES.MODELOS.USAR') }}
            <span
              class="i-lucide-arrow-right size-4 rtl:rotate-180"
              aria-hidden="true"
            />
          </span>
        </span>
        <span class="flex flex-col gap-1.5">
          <span class="text-lg font-semibold leading-snug text-n-slate-12">
            {{ $t(`AUTOMACOES.MODELOS.${modelo.chave}.TITULO`) }}
          </span>
          <span class="text-[0.9375rem] leading-relaxed text-n-slate-11">
            {{ $t(`AUTOMACOES.MODELOS.${modelo.chave}.TEXTO`) }}
          </span>
        </span>
        <span
          class="flex flex-col w-full gap-2 pt-4 mt-auto border-t border-dashed border-n-weak text-sm text-n-slate-11"
        >
          <span class="flex items-baseline gap-3">
            <span
              class="w-14 shrink-0 text-xs font-semibold tracking-wider uppercase text-n-slate-10"
            >
              {{ $t('AUTOMACOES.MODELOS.ROTULO_QUANDO') }}
            </span>
            {{ $t(`AUTOMACOES.MODELOS.${modelo.chave}.QUANDO`) }}
          </span>
          <span class="flex items-baseline gap-3">
            <span
              class="w-14 shrink-0 text-xs font-semibold tracking-wider uppercase text-n-slate-10"
            >
              {{ $t('AUTOMACOES.MODELOS.ROTULO_FAZ') }}
            </span>
            {{ $t(`AUTOMACOES.MODELOS.${modelo.chave}.FAZ`) }}
          </span>
        </span>
      </button>
    </li>
  </ul>
</template>
