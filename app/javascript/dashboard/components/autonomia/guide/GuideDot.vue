<script setup>
// #697 — ponto de destaque no botão do Guia até a primeira abertura. Pulsa só 3
// vezes (nada de animação contínua) e não pulsa para quem pede movimento reduzido.
// #935 — com `numero`, vira a bolinha com a contagem de avisos novos. O nome
// acessível ("2 avisos novos") vai no próprio botão; a bolinha é só visual.
defineProps({
  numero: { type: Number, default: 0 },
});
</script>

<template>
  <span
    v-if="numero > 0"
    data-guia-ponto
    data-guia-numero
    aria-hidden="true"
    class="absolute -top-1.5 ltr:-right-1.5 rtl:-left-1.5 flex pointer-events-none"
  >
    <span
      class="absolute inset-0 rounded-full bg-n-amber-9 opacity-75 motion-safe:animate-[ping_1.2s_cubic-bezier(0,0,0.2,1)_3]"
    />
    <span
      class="relative flex items-center justify-center min-w-5 h-5 px-1 rounded-full bg-n-amber-9 ring-2 ring-n-background text-xs font-medium tabular-nums text-n-amber-12 dark:text-n-amber-3"
    >
      {{ numero > 9 ? '9+' : numero }}
    </span>
  </span>
  <span
    v-else
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
