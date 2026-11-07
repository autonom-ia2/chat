<script setup>
// #2692 — rodada 3: nas telas sem rodapé, no celular, uma faixa vazia colada
// embaixo, igual ao rodapé, onde o botão redondo do menu
// (MobileSidebarLauncher.vue: fixed bottom-4 left-4) fica sem cobrir nada.
// Rodada 5 (F2): sem botão principal, a faixa não aparece; fica só o espaço,
// e o botão redondo flutua sozinho.
</script>

<template>
  <div class="h-20 shrink-0 md:hidden" aria-hidden="true" data-faixa-menu />
</template>
