<script setup>
// A caixinha de marcar do WhatsApp Web (#1702): quadrada, 18 px, borda cinza de
// 2 px; marcada, fundo verde com o tique branco. Só desenho: quem tem o papel de
// checkbox (teclado, leitor de tela) é o botão em volta.
import Icon from 'next/icon/Icon.vue';

defineProps({
  marcada: { type: Boolean, default: false },
});
</script>

<template>
  <span
    class="grid place-content-center size-[18px] shrink-0 rounded-[3px] border-2 transition-colors"
    :class="
      marcada
        ? 'bg-[#00A884] border-[#00A884] text-white'
        : 'bg-transparent border-[#8696A0] dark:border-[#8696A0]'
    "
    aria-hidden="true"
  >
    <Icon v-if="marcada" icon="i-ph-check-bold" class="size-3" />
  </span>
</template>
