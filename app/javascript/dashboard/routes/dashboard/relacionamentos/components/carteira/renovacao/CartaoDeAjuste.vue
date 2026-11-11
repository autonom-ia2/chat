<script setup>
import { useId } from 'vue';

// #2897 — um cartão de "Como as renovações andam": uma pergunta e a resposta
// dela. O título nomeia a região e o grupo de escolha de dentro (`rotuloId`).
defineProps({
  titulo: { type: String, required: true },
  marca: { type: String, required: true },
});

const rotuloId = useId();
</script>

<template>
  <section
    :data-carteira="marca"
    :aria-labelledby="rotuloId"
    class="flex flex-col min-w-0 gap-4 p-5 border shadow-sm rounded-2xl border-n-weak bg-n-solid-1 md:p-6"
  >
    <h2
      :id="rotuloId"
      class="m-0 text-xl font-semibold tracking-tight text-n-slate-12"
    >
      {{ titulo }}
    </h2>
    <slot :rotulo-id="rotuloId" />
  </section>
</template>
