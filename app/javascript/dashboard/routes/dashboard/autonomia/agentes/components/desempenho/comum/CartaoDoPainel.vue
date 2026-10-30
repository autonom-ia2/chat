<script setup>
import { useId } from 'vue';

// #2226 v2 — o cartão de todo bloco do painel (Resumo e Detalhe): título de 14px, descrição curta e,
// no rodapé, a unidade do que se conta ("Unidade: procuras…"). O slot `acoes` fica no canto de cima.
defineProps({
  titulo: { type: String, default: '' },
  descricao: { type: String, default: '' },
  unidade: { type: String, default: '' },
});

const idDoTitulo = useId();
</script>

<template>
  <section
    data-cartao
    :aria-labelledby="titulo ? idDoTitulo : undefined"
    class="flex flex-col min-w-0 gap-3 p-5 shadow-sm rounded-2xl bg-n-solid-1 ring-1 ring-n-weak dark:shadow-none"
  >
    <header
      v-if="titulo || descricao || $slots.acoes"
      class="flex flex-wrap items-start justify-between gap-x-4 gap-y-2"
    >
      <div class="flex flex-col min-w-0 gap-0.5">
        <h3
          v-if="titulo"
          :id="idDoTitulo"
          class="m-0 text-sm font-semibold text-n-slate-12"
        >
          {{ titulo }}
        </h3>
        <p v-if="descricao" class="m-0 text-xs text-n-slate-11">
          {{ descricao }}
        </p>
      </div>
      <div
        v-if="$slots.acoes"
        class="flex flex-wrap items-center max-w-full min-w-0 gap-2"
      >
        <slot name="acoes" />
      </div>
    </header>
    <slot />
    <p
      v-if="unidade"
      data-unidade
      class="pt-2 m-0 mt-auto text-xs border-t text-n-slate-11 border-n-weak"
    >
      {{ unidade }}
    </p>
  </section>
</template>
