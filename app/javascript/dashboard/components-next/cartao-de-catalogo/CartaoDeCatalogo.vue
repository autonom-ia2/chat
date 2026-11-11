<script setup>
import { classeDoTom } from './tons';
// #2889 — o cartão de um item de catálogo (modelo de automação, e no futuro a ferramenta pronta da vitrine #2858):
// ícone num quadrado com o tom do grupo, título, um apoio opcional, a frase do que faz e um selo. O cartão inteiro é o
// botão que abre o detalhe. Recebe o texto pronto, sem depender do caminho do i18n, para servir a qualquer catálogo.
defineProps({
  titulo: { type: String, required: true },
  texto: { type: String, default: '' },
  apoio: { type: String, default: '' },
  icone: { type: String, required: true },
  tom: { type: String, default: 'azul' },
  // { texto, icone } ou null.
  selo: { type: Object, default: null },
  destaque: { type: Boolean, default: false },
});

const emit = defineEmits(['abrir']);
</script>

<template>
  <button
    type="button"
    data-cartao-de-catalogo
    class="flex flex-col w-full h-full gap-3 p-5 transition shadow-sm text-start rounded-2xl bg-n-solid-1 ring-1 ring-inset hover:-translate-y-0.5 hover:shadow-md focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-n-blue-11 motion-reduce:transition-none motion-reduce:hover:translate-y-0"
    :class="destaque ? 'ring-n-blue-6' : 'ring-n-weak hover:ring-n-blue-6'"
    @click="emit('abrir')"
  >
    <span class="flex items-start gap-3">
      <span
        aria-hidden="true"
        class="grid rounded-xl place-items-center size-11 shrink-0"
        :class="classeDoTom(tom)"
      >
        <span :class="icone" class="size-6" />
      </span>
      <span class="flex flex-col min-w-0 gap-0.5">
        <span class="text-base font-semibold leading-snug text-n-slate-12">
          {{ titulo }}
        </span>
        <span v-if="apoio" class="text-xs text-n-slate-11">
          {{ apoio }}
        </span>
      </span>
    </span>
    <span v-if="texto" class="flex-1 text-sm leading-relaxed text-n-slate-11">
      {{ texto }}
    </span>
    <span
      v-if="selo"
      class="inline-flex items-center self-start gap-1.5 px-2.5 py-1 text-xs font-medium rounded-lg bg-n-iris-3 text-n-iris-11"
    >
      <span :class="selo.icone" class="size-3.5" aria-hidden="true" />
      {{ selo.texto }}
    </span>
  </button>
</template>
