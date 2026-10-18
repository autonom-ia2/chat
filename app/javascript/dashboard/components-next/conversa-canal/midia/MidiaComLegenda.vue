<script setup>
// #1702: foto ou vídeo com legenda, no tamanho do app (formatoDaMidia), em cima da
// legenda. Revisão de 17/10: com legenda a mídia ia para os chips do Chatwoot e saía
// fora da regra de proporção (9:16 virava 330x330 mostrando só o topo). Tocar abre a
// galeria, como na mensagem sem legenda.
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useSnakeCase } from 'dashboard/composables/useTransformKeys';
import GalleryView from 'dashboard/components/widgets/conversation/components/GalleryView.vue';
import { useMessageContext } from '../../message/provider.js';
import { ATTACHMENT_TYPES } from '../../message/constants';
import VideoDoWhatsapp from './VideoDoWhatsapp.vue';
import { formatoDaMidia } from './proporcaoDaMidia';

const props = defineProps({
  anexo: { type: Object, required: true },
});

const { t } = useI18n();
const { filteredCurrentChatAttachments } = useMessageContext();
const galeria = ref(false);
const falhou = ref(false);

const ehVideo = computed(() => props.anexo.fileType === ATTACHMENT_TYPES.VIDEO);
const medidasCarregadas = ref({ largura: 0, altura: 0 });
const formatoDaFoto = computed(() =>
  formatoDaMidia(
    props.anexo.width || medidasCarregadas.value.largura,
    props.anexo.height || medidasCarregadas.value.altura
  )
);
const lerMedidas = ({ target }) => {
  medidasCarregadas.value = {
    largura: target.naturalWidth,
    altura: target.naturalHeight,
  };
};
</script>

<template>
  <div
    class="overflow-hidden rounded-[8px] cursor-pointer w-fit max-w-full"
    data-midia-do-whatsapp
    @click="galeria = true"
  >
    <VideoDoWhatsapp v-if="ehVideo" :attachment="anexo" />
    <div
      v-else-if="falhou"
      class="grid place-content-center gap-1 w-[330px] max-w-full h-[180px] text-[13px] text-[#666666] dark:text-[#A7A8A8] bg-[#0A0A0A]/5 dark:bg-white/5"
    >
      <span class="i-ph-image-broken size-6 mx-auto" aria-hidden="true" />
      {{ t('COMPONENTS.MEDIA.LOADING_FAILED') }}
    </div>
    <img
      v-else
      :src="anexo.dataUrl"
      alt=""
      loading="lazy"
      class="block skip-context-menu"
      :class="formatoDaFoto"
      @load="lerMedidas"
      @error="falhou = true"
    />
  </div>
  <GalleryView
    v-if="galeria"
    v-model:show="galeria"
    :attachment="useSnakeCase(anexo)"
    :all-attachments="filteredCurrentChatAttachments"
    @close="() => (galeria = false)"
  />
</template>
