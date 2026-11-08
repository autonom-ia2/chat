<script setup>
// Foto, vídeo, reel e figurinha do Direct (#2079): sem balão, com os cantos do grupo.
// O reel leva o ícone "Clipe"; o vídeo, o ▶ no meio; a figurinha fica solta, 157 px.
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { ATTACHMENT_TYPES } from 'dashboard/components-next/message/constants';
import { INDISPONIVEL } from './visualInstagram';

const props = defineProps({
  anexo: { type: Object, required: true },
  cantos: { type: Object, default: () => ({}) },
  figurinha: { type: Boolean, default: false },
});

const { t } = useI18n();
// Mídia que não abre (cópia ausente e endereço da Meta expirado): "Mídia indisponível".
const quebrou = ref(false);
const ehVideo = computed(() =>
  [ATTACHMENT_TYPES.VIDEO, ATTACHMENT_TYPES.IG_REEL].includes(
    props.anexo.fileType
  )
);
const ehReel = computed(
  () => props.anexo.fileType === ATTACHMENT_TYPES.IG_REEL
);
const rotulo = computed(() =>
  t(
    ehVideo.value
      ? 'CONVERSA_CANAL.INSTAGRAM.ABRIR_VIDEO'
      : 'CONVERSA_CANAL.INSTAGRAM.ABRIR_FOTO'
  )
);
const tamanho = computed(() => {
  if (props.figurinha) return 'size-[157px]';
  if (ehReel.value) return 'w-[200px] h-[355px]';
  return 'max-w-[236px] max-h-[340px]';
});
</script>

<template>
  <div
    v-if="quebrou"
    :class="[INDISPONIVEL, figurinha ? 'size-[157px]' : 'w-[236px] h-[160px]']"
    :style="figurinha ? {} : cantos"
    role="img"
    :aria-label="t('CONVERSA_CANAL.INSTAGRAM.MIDIA_INDISPONIVEL')"
  >
    <span class="i-ph-image-broken size-4 shrink-0" />
    {{ t('CONVERSA_CANAL.INSTAGRAM.MIDIA_INDISPONIVEL') }}
  </div>
  <a
    v-else
    :href="anexo.dataUrl"
    target="_blank"
    rel="noopener noreferrer"
    :aria-label="rotulo"
    class="relative block overflow-hidden"
    :class="tamanho"
    :style="figurinha ? {} : cantos"
  >
    <video
      v-if="ehVideo"
      :src="anexo.dataUrl"
      preload="metadata"
      muted
      playsinline
      class="block object-cover"
      :class="ehReel ? 'size-full' : 'max-w-[236px] max-h-[340px]'"
      @error="quebrou = true"
    />
    <img
      v-else
      :src="anexo.dataUrl"
      alt=""
      class="block"
      :class="
        figurinha
          ? 'size-full object-contain'
          : 'max-w-[236px] max-h-[340px] object-cover'
      "
      @error="quebrou = true"
    />
    <span
      v-if="ehVideo && !ehReel"
      class="absolute inset-0 flex items-center justify-center pointer-events-none"
    >
      <span class="i-ph-play-fill size-10 text-white drop-shadow" />
    </span>
    <span
      v-if="ehReel"
      class="absolute top-3 ltr:right-3 rtl:left-3 i-ph-film-reel-fill size-6 text-white drop-shadow pointer-events-none"
      :aria-label="t('CONVERSA_CANAL.INSTAGRAM.CLIPE')"
    />
  </a>
</template>
