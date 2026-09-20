<script setup>
import Button from 'dashboard/components-next/button/Button.vue';

// Cabeçalho próprio do Guia, em vez do SidebarActionsHeader compartilhado.
// Dois motivos, ambos de acessibilidade e toque:
//  - lá os botões são 32x32 e ficam colados; errar o alvo e acertar "Nova
//    conversa" apaga a conversa inteira sem confirmação. Aqui são 48x48 com
//    espaço entre eles;
//  - lá o nome do botão só existe como tooltip, que leitor de tela não lê.
//    Aqui cada botão tem aria-label.
defineProps({
  title: {
    type: String,
    required: true,
  },
  // Só há o que reiniciar quando a conversa já começou.
  canReset: {
    type: Boolean,
    default: false,
  },
});

defineEmits(['reset', 'close']);
</script>

<template>
  <div
    class="flex items-center justify-between gap-2 px-3 py-1 border-b border-n-weak"
  >
    <h2 class="mb-0 min-w-0 text-sm font-medium truncate text-n-slate-12">
      {{ title }}
    </h2>
    <div class="flex items-center gap-2 shrink-0">
      <Button
        v-if="canReset"
        v-tooltip="$t('AUTONOMIA_GUIDE.RESET')"
        :aria-label="$t('AUTONOMIA_GUIDE.A11Y.NEW_CONVERSATION')"
        icon="i-lucide-refresh-ccw"
        ghost
        slate
        lg
        @click="$emit('reset')"
      />
      <Button
        v-tooltip="$t('AUTONOMIA_GUIDE.A11Y.CLOSE')"
        :aria-label="$t('AUTONOMIA_GUIDE.A11Y.CLOSE')"
        icon="i-lucide-x"
        ghost
        slate
        lg
        @click="$emit('close')"
      />
    </div>
  </div>
</template>
