<script setup>
import PreviaSelo from './PreviaSelo.vue';

// #1385 — moldura da coluna da direita, igual à do funil (#1384): selo, título e uma frase.
defineProps({
  titulo: { type: String, required: true },
  texto: { type: String, default: '' },
  selo: { type: String, default: 'previa' },
});
</script>

<template>
  <section data-passagem-previa class="flex flex-col gap-4">
    <header class="flex flex-col gap-1">
      <span class="flex flex-wrap items-center gap-2">
        <PreviaSelo :tipo="selo" />
        <h2 class="mb-0 text-base font-semibold text-n-slate-12">
          {{ titulo }}
        </h2>
      </span>
      <p v-if="texto" class="mb-0 text-sm text-n-slate-11">{{ texto }}</p>
    </header>
    <slot />
  </section>
</template>
