<script setup>
// Só emoji (#1702): 1 a 3 emojis sem texto aparecem grandes e sem balão, como no
// WhatsApp; quanto mais emojis, menores. A hora fica num selo pequeno embaixo
// (classesDaHora em visualWhatsapp.js). Quem escolhe este balão é Message.vue, com a pele.
import { computed } from 'vue';
import BaseBubble from '../../message/bubbles/Base.vue';
import { useMessageContext } from '../../message/provider.js';
import { contarSoEmojis } from '../soEmoji';

const { content } = useMessageContext();

// Classes literais por quantidade (o Tailwind só gera o que lê no código).
const TAMANHOS = {
  1: 'text-[48px] leading-[58px]',
  2: 'text-[40px] leading-[48px]',
  3: 'text-[32px] leading-[40px]',
};

const tamanho = computed(() => TAMANHOS[contarSoEmojis(content.value)] || '');
</script>

<template>
  <BaseBubble data-bubble-name="emoji">
    <p class="m-0 px-1 select-text" :class="tamanho" data-emoji-grande>
      {{ content.trim() }}
    </p>
  </BaseBubble>
</template>
