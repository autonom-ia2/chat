<script setup>
import { computed } from 'vue';

// Anúncios da Meta (#2198): a foto ou o vídeo dentro da prévia. Vídeo mostra a capa (tirada no navegador) com o
// botão de play; sem capa, o próprio vídeo parado no primeiro quadro. Sem mídia, diz onde ela vai aparecer.
const props = defineProps({
  media: { type: Object, default: null },
  // 'cover' preenche o quadro; 'contain' mostra inteira.
  fit: { type: String, default: 'cover' },
  // Fundo dos Stories: só a imagem, sem play nem frase.
  backdrop: { type: Boolean, default: false },
  // Ocupa o quadro inteiro do pai (cartão do carrossel): todos os cartões com a mesma altura, sem vazio.
  fill: { type: Boolean, default: false },
});

const KEY = 'CRM_KANBAN.META_ADS_HUB.CRIAR.PREVIEW';

const isVideo = computed(() => props.media?.kind === 'video');
const still = computed(() => {
  if (!props.media) return '';
  return isVideo.value ? props.media.poster || '' : props.media.url;
});
const fitClass = computed(() => [
  props.fit === 'contain' ? 'object-contain' : 'object-cover',
  props.fill ? 'absolute inset-0 h-full w-full' : '',
]);
</script>

<template>
  <img
    v-if="still"
    :src="still"
    alt=""
    :aria-hidden="backdrop || undefined"
    class="size-full"
    :class="fitClass"
  />
  <video
    v-else-if="isVideo && media.url && !backdrop"
    :src="media.url"
    muted
    playsinline
    preload="metadata"
    class="size-full"
    :class="fitClass"
  />
  <div
    v-else-if="!media && !backdrop"
    data-create-preview-empty
    class="flex size-full flex-col items-center justify-center gap-2 p-4 text-center"
  >
    <span class="i-lucide-image size-8" aria-hidden="true" />
    <span class="text-xs">{{ $t(`${KEY}.EMPTY`) }}</span>
  </div>
  <span
    v-if="isVideo && !backdrop"
    class="i-lucide-circle-play absolute left-1/2 top-1/2 size-12 -translate-x-1/2 -translate-y-1/2 text-white drop-shadow"
    aria-hidden="true"
  />
</template>
