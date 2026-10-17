<script setup>
import { ref, computed } from 'vue';
import BaseBubble from './Base.vue';
import Icon from 'next/icon/Icon.vue';
import { useSnakeCase } from 'dashboard/composables/useTransformKeys';
import { useMessageContext } from '../provider.js';
import GalleryView from 'dashboard/components/widgets/conversation/components/GalleryView.vue';
import { ATTACHMENT_TYPES } from '../constants';
import VideoDoWhatsapp from '../../conversa-canal/midia/VideoDoWhatsapp.vue';
import { usePele } from '../../conversa-canal/pele';

const emit = defineEmits(['error']);

// #1702: com a pele do WhatsApp, a miniatura com o play do app (tocar abre a galeria).
const pele = usePele();

const hasError = ref(false);
const showGallery = ref(false);
const { filteredCurrentChatAttachments, attachments } = useMessageContext();

const handleError = () => {
  hasError.value = true;
  emit('error');
};

const attachment = computed(() => {
  return attachments.value[0];
});

const isReel = computed(() => {
  return attachment.value.fileType === ATTACHMENT_TYPES.IG_REEL;
});
</script>

<template>
  <BaseBubble
    class="overflow-hidden p-3"
    data-bubble-name="video"
    @click="showGallery = true"
  >
    <VideoDoWhatsapp v-if="pele && !isReel" :attachment="attachment" />
    <div v-else class="relative group rounded-lg overflow-hidden">
      <div
        v-if="isReel"
        class="absolute p-2 flex items-start justify-end right-0 pointer-events-none"
      >
        <Icon icon="i-lucide-instagram" class="text-white shadow-lg" />
      </div>
      <video
        controls
        class="rounded-lg skip-context-menu"
        :src="attachment.dataUrl"
        :class="{
          'max-w-48': isReel,
          'max-w-full': !isReel,
        }"
        @click.stop
        @error="handleError"
      />
    </div>
  </BaseBubble>
  <GalleryView
    v-if="showGallery"
    v-model:show="showGallery"
    :attachment="useSnakeCase(attachment)"
    :all-attachments="filteredCurrentChatAttachments"
    @error="onError"
    @close="() => (showGallery = false)"
  />
</template>
