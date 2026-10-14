<script setup>
// Moldura das mensagens ricas: cabeçalho, corpo (`content`), rodapé e anexos como o cliente recebeu;
// a interação vai no slot padrão. O slot `header` substitui o cabeçalho em texto (ex.: imagem).
import { useSlots } from 'vue';
import BaseBubble from '../Base.vue';
import FormattedContent from '../Text/FormattedContent.vue';
import AttachmentChips from '../../chips/AttachmentChips.vue';
import { useMessageContext } from '../../provider.js';

defineProps({
  bubbleName: { type: String, required: true },
  header: { type: String, default: '' },
  footer: { type: String, default: '' },
});

const slots = useSlots();
const { content, attachments } = useMessageContext();
</script>

<template>
  <BaseBubble class="px-4 py-3 min-w-64" :data-bubble-name="bubbleName">
    <div class="flex flex-col gap-3">
      <div
        v-if="slots.header || header || content || footer"
        class="flex flex-col gap-1"
      >
        <slot name="header">
          <div v-if="header" class="font-medium break-words">{{ header }}</div>
        </slot>
        <FormattedContent v-if="content" :content="content" />
        <div v-if="footer" class="text-xs text-n-slate-11 break-words">
          {{ footer }}
        </div>
      </div>
      <AttachmentChips
        v-if="attachments?.length"
        :attachments="attachments"
        class="gap-2"
      />
      <slot />
    </div>
  </BaseBubble>
</template>
