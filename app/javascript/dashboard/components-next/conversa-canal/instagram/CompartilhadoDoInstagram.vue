<script setup>
// Post e story compartilhados no Direct (#2079). O story (menção, story e resposta ao
// story) vem com o rótulo em cima e a barra de citação ao lado da miniatura de 158 px;
// sem a mídia, fica "Story indisponível". O post é o cartão de 300 px, com "Mídia
// indisponível" quando a mídia não abre (sem a nossa cópia, o link da Meta expira).
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { ATTACHMENT_TYPES } from 'dashboard/components-next/message/constants';
import { BALOES } from './balaoDoInstagram';
import {
  BARRA_DE_CITACAO,
  ELEVADO,
  INDISPONIVEL,
  ROTULO,
  TEXTO,
} from './visualInstagram';

const props = defineProps({
  tipo: { type: String, required: true },
  mensagem: { type: Object, required: true },
  enviada: { type: Boolean, default: false },
});

const { t } = useI18n();
const anexo = computed(() => props.mensagem.attachments?.[0] || null);
const quebrou = ref(false);
// Story e post em vídeo também chegam como ig_story/ig_post: a foto falhou, tenta o vídeo antes de desistir.
const tentarVideo = ref(false);
const ehVideo = computed(
  () => anexo.value?.fileType === ATTACHMENT_TYPES.VIDEO
);
const temMidia = computed(
  () => Boolean(anexo.value?.dataUrl) && !quebrou.value
);

const rotuloDoStory = computed(() => {
  const tipo = props.mensagem.contentAttributes?.imageType;
  if (tipo === ATTACHMENT_TYPES.IG_STORY_REPLY) {
    return props.enviada
      ? t('CONVERSA_CANAL.INSTAGRAM.VOCE_RESPONDEU_AO_STORY')
      : t('CONVERSA_CANAL.INSTAGRAM.RESPONDEU_AO_STORY');
  }
  if (tipo === ATTACHMENT_TYPES.STORY_MENTION) {
    return props.enviada
      ? t('CONVERSA_CANAL.INSTAGRAM.VOCE_MENCIONOU_NO_STORY')
      : t('CONVERSA_CANAL.INSTAGRAM.MENCIONOU_NO_STORY');
  }
  return '';
});
</script>

<template>
  <div
    v-if="tipo === BALOES.STORY"
    class="flex flex-col gap-1"
    :class="enviada ? 'items-end' : 'items-start'"
  >
    <span v-if="rotuloDoStory" :class="ROTULO">{{ rotuloDoStory }}</span>
    <div
      class="flex items-stretch gap-2"
      :class="{ 'flex-row-reverse': enviada }"
    >
      <span :class="BARRA_DE_CITACAO" />
      <a
        v-if="temMidia"
        :href="anexo.dataUrl"
        target="_blank"
        rel="noopener noreferrer"
        class="block w-[158px] h-[237px] overflow-hidden rounded-[18px]"
      >
        <video
          v-if="ehVideo || tentarVideo"
          :src="anexo.dataUrl"
          preload="metadata"
          muted
          playsinline
          class="size-full object-cover"
          @error="quebrou = true"
        />
        <img
          v-else
          :src="anexo.dataUrl"
          alt=""
          class="size-full object-cover"
          @error="tentarVideo = true"
        />
      </a>
      <span v-else :class="ROTULO" class="py-1">
        {{ t('CONVERSA_CANAL.INSTAGRAM.STORY_INDISPONIVEL') }}
      </span>
    </div>
  </div>
  <div
    v-else
    class="w-[300px] overflow-hidden rounded-[18px]"
    :class="[ELEVADO, TEXTO]"
  >
    <div class="p-3 text-sm font-bold leading-[18px]">
      {{ t('CONVERSA_CANAL.INSTAGRAM.POST') }}
    </div>
    <a
      v-if="temMidia"
      :href="anexo.dataUrl"
      target="_blank"
      rel="noopener noreferrer"
      class="block"
    >
      <video
        v-if="ehVideo || tentarVideo"
        :src="anexo.dataUrl"
        preload="metadata"
        muted
        playsinline
        class="block w-[300px] h-[375px] object-cover"
        @error="quebrou = true"
      />
      <img
        v-else
        :src="anexo.dataUrl"
        alt=""
        class="block w-[300px] h-[375px] object-cover"
        @error="tentarVideo = true"
      />
    </a>
    <div v-else class="h-[120px] rounded-none" :class="INDISPONIVEL">
      <span class="i-ph-image-broken size-4 shrink-0" />
      {{ t('CONVERSA_CANAL.INSTAGRAM.MIDIA_INDISPONIVEL') }}
    </div>
  </div>
</template>
