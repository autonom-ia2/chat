<script setup>
// #2692 — rodada 3: nas telas sem rodapé, no celular, uma faixa vazia colada
// embaixo, igual ao rodapé, onde o botão redondo do menu
// (MobileSidebarLauncher.vue: fixed bottom-4 left-4) fica sem cobrir nada.
// Rodada 5 (F2): sem botão principal, a faixa não aparece; fica só o espaço,
// e o botão redondo flutua sozinho.
// D3 (crítica r5): o espaço é a altura do botão redondo (48 px) + 16 px de
// distância da borda + 16 px de folga, com sobra, para o último item da
// lista nunca ficar embaixo dele.
</script>

<template>
  <div class="h-24 shrink-0 md:hidden" aria-hidden="true" data-faixa-menu />
</template>
