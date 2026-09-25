<script setup>
// #697 — ponto de destaque no botão do Guia até a primeira abertura. Pulsa só 3
// vezes (nada de animação contínua) e não pulsa para quem pede movimento reduzido.
</script>

<template>
  <span
    data-guia-ponto
    aria-hidden="true"
    class="absolute -top-0.5 ltr:-right-0.5 rtl:-left-0.5 flex size-3.5 pointer-events-none"
  >
    <span
      class="absolute inset-0 rounded-full bg-n-amber-9 opacity-75 motion-safe:animate-[ping_1.2s_cubic-bezier(0,0,0.2,1)_3]"
    />
    <span
      class="relative size-3.5 rounded-full bg-n-amber-9 ring-2 ring-n-background"
    />
  </span>
</template>
