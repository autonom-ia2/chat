<script setup>
import LivreJornada from '../components/LivreJornada.vue';

// #2414 F0 — moldura do protótipo: a tela da vez e o mapa da jornada no canto.
</script>

<template>
  <section class="relative flex flex-col w-full h-full overflow-hidden">
    <router-view />
    <LivreJornada />
  </section>
</template>
