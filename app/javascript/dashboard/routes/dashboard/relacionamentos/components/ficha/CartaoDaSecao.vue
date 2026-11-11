<script setup>
import { useId } from 'vue';

// #2894 — o cartão de cada bloco da ficha: título forte, a ação discreta do
// canto (se houver) e o conteúdo. O título nomeia a região para o leitor de tela.
defineProps({
  titulo: { type: String, required: true },
});

const idDoTitulo = useId();
</script>

<template>
  <section
    :aria-labelledby="idDoTitulo"
    class="p-5 border shadow-sm rounded-2xl border-n-weak bg-n-solid-1 md:p-6"
  >
    <header class="flex items-center justify-between gap-3 mb-4">
      <h2
        :id="idDoTitulo"
        class="m-0 text-xl font-semibold tracking-tight text-n-slate-12"
      >
        {{ titulo }}
      </h2>
      <slot name="acao" />
    </header>
    <slot />
  </section>
</template>
