// Um relógio só para a conversa inteira (#1702), de minuto em minuto, em segundos:
// as etiquetas de dia mudam à meia-noite sem cada uma ter o seu cronômetro.
import { computed } from 'vue';
import { createSharedComposable, useNow } from '@vueuse/core';

const UM_MINUTO = 60 * 1000;

export const useAgora = createSharedComposable(() => {
  const agora = useNow({ interval: UM_MINUTO });
  return computed(() => Math.floor(agora.value.getTime() / 1000));
});
