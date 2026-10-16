<script setup>
// Vídeo no balão com a cara do WhatsApp (#1702): a primeira imagem do vídeo, o play
// redondo no meio e a duração embaixo, à esquerda. Tocar abre a galeria (o clique
// sobe para o balão); a hora fica por cima, no canto, como na foto.
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { tempoDoAudio } from '../audio/ondaDoAudio';

const props = defineProps({
  attachment: { type: Object, required: true },
});

const { t } = useI18n();
const duracao = ref(0);
const tempo = computed(() =>
  duracao.value ? tempoDoAudio(duracao.value) : ''
);
// "#t=0.1" faz o navegador mostrar a primeira imagem sem tocar.
const endereco = computed(() => `${props.attachment.dataUrl}#t=0.1`);
</script>

<template>
  <div
    class="relative overflow-hidden rounded-[8px] bg-[#000]/80"
    data-video-do-whatsapp
  >
    <video
      class="block w-[330px] max-w-full max-h-[330px] object-cover skip-context-menu"
      preload="metadata"
      muted
      playsinline
      :src="endereco"
      @loadedmetadata="duracao = $event.target.duration || 0"
    />
    <span
      class="absolute inset-0 m-auto grid place-content-center size-12 rounded-full bg-[#000]/45 text-white pointer-events-none"
      role="img"
      :aria-label="t('CONVERSA_CANAL.MIDIA.VIDEO')"
    >
      <span class="i-ph-play-fill size-6 ms-0.5" aria-hidden="true" />
    </span>
    <span
      v-if="tempo"
      class="absolute bottom-[6px] ltr:left-[8px] rtl:right-[8px] z-[1] flex items-center gap-1 text-[11px] leading-[15px] text-white [text-shadow:0_1px_1px_rgba(0,0,0,0.5)] pointer-events-none"
    >
      <span class="i-ph-video-camera-fill size-3.5" aria-hidden="true" />
      {{ tempo }}
    </span>
  </div>
</template>
