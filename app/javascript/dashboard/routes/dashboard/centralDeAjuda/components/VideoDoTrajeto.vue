<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useTamanhoDaLetra } from '../composables/useTamanhoDaLetra';

// Vídeo curto do caminho na tela, sem som. Não começa sozinho: quem lê devagar dá o play quando quiser.
// A legenda é texto (.vtt), não gravada na imagem, e acompanha o tamanho de letra escolhido na Central.
defineProps({
  video: { type: Object, required: true },
});

const { t } = useI18n();
const { tamanho } = useTamanhoDaLetra();

const CLASSES = { normal: 'text-base', grande: 'text-lg', maior: 'text-xl' };
const classeDaLetra = computed(() => CLASSES[tamanho.value]);
</script>

<template>
  <figure class="m-0 flex flex-col gap-2">
    <figcaption class="text-base font-medium text-n-slate-12">
      {{ t('HELP_CENTER.CENTRAL_DE_AJUDA.ARTIGO.VIDEO') }}
    </figcaption>
    <video
      :src="video.arquivo"
      :poster="video.poster"
      controls
      preload="metadata"
      playsinline
      class="w-full rounded-xl border border-n-weak bg-n-slate-3 [&::cue]:text-[1em]"
      :class="classeDaLetra"
    >
      <track
        v-if="video.legenda"
        kind="captions"
        srclang="pt-BR"
        :label="t('HELP_CENTER.CENTRAL_DE_AJUDA.ARTIGO.VIDEO_LEGENDA')"
        :src="video.legenda"
        default
      />
    </video>
  </figure>
</template>
