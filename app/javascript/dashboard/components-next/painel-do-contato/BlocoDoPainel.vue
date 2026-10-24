<script setup>
// #2138 — um bloco do painel: título curto (maior e mais forte que o conteúdo,
// sem caixa alta) e o conteúdo. Bloco sem conteúdo não é desenhado por quem usa.
defineProps({
  titulo: { type: String, default: '' },
});
</script>

<template>
  <section
    class="flex flex-col gap-2 px-4 py-4 border-t border-n-weak first:border-t-0"
  >
    <h3
      v-if="titulo"
      class="m-0 text-base font-semibold leading-6 text-n-slate-12"
    >
      {{ titulo }}
    </h3>
    <slot />
  </section>
</template>
