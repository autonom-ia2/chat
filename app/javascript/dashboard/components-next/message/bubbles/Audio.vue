<script setup>
import { computed } from 'vue';
import BaseBubble from './Base.vue';
import AudioChip from 'next/message/chips/Audio.vue';
import { useMessageContext } from '../provider.js';
import AudioDoWhatsapp from '../../conversa-canal/audio/AudioDoWhatsapp.vue';
import { usePele } from '../../conversa-canal/pele';

// #1702: com a pele do WhatsApp, o áudio com a onda do app.
const pele = usePele();

const { attachments } = useMessageContext();

const attachment = computed(() => {
  return attachments.value[0];
});
</script>

<template>
  <BaseBubble class="bg-transparent" data-bubble-name="audio">
    <AudioDoWhatsapp v-if="pele" :attachment="attachment" />
    <AudioChip
      v-else
      :attachment="attachment"
      class="p-2 text-n-slate-12 skip-context-menu"
    />
  </BaseBubble>
</template>
