<script setup>
// Moldura das mensagens ricas: cabeçalho, corpo (`content`) e rodapé como o cliente recebeu; a interação vai no slot.
import BaseBubble from '../Base.vue';
import FormattedContent from '../Text/FormattedContent.vue';
import { useMessageContext } from '../../provider.js';

defineProps({
  bubbleName: { type: String, required: true },
  header: { type: String, default: '' },
  footer: { type: String, default: '' },
});

const { content } = useMessageContext();
</script>

<template>
  <BaseBubble class="px-4 py-3 min-w-64" :data-bubble-name="bubbleName">
    <div class="flex flex-col gap-3">
      <div v-if="header || content || footer" class="flex flex-col gap-1">
        <div v-if="header" class="font-medium break-words">{{ header }}</div>
        <FormattedContent v-if="content" :content="content" />
        <div v-if="footer" class="text-xs text-n-slate-11 break-words">
          {{ footer }}
        </div>
      </div>
      <slot />
    </div>
  </BaseBubble>
</template>
