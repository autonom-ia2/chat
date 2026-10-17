<script setup>
// Botão redondo de encaminhar ao lado do balão de mídia (foto, vídeo, documento,
// localização, contato), como no WhatsApp Web (#1702): aparece ao passar o mouse,
// FORA do balão, e abre direto a janela "Encaminhar mensagem para".
import { useI18n } from 'vue-i18n';
import Icon from 'next/icon/Icon.vue';
import { ORIENTATION } from '../../message/constants';

defineProps({
  lado: { type: String, required: true },
});
const emit = defineEmits(['encaminhar']);
const { t } = useI18n();
</script>

<template>
  <div
    class="self-center shrink-0"
    :class="lado === ORIENTATION.RIGHT ? 'order-first' : ''"
    data-encaminhar-do-balao
  >
    <button
      v-tooltip.top="t('CONVERSA_CANAL.ENCAMINHAR.BOTAO')"
      type="button"
      class="grid place-content-center size-11 rounded-full text-[#8C8C8C] dark:text-[#A7A8A8] hover:text-[#54656F] dark:hover:text-[#D1D7DB] transition-opacity opacity-0 group-hover/linha:opacity-100 focus-visible:opacity-100 [@media(hover:none)]:hidden"
      :aria-label="t('CONVERSA_CANAL.ENCAMINHAR.BOTAO')"
      @click.stop="emit('encaminhar')"
    >
      <!-- O círculo do app tem 32 px; a área de toque, 44 px. -->
      <span
        class="grid place-content-center size-8 rounded-full bg-white/80 dark:bg-[#242626]/80 shadow-[0_1px_1px_rgba(11,20,26,0.13)]"
      >
        <Icon icon="i-ph-arrow-bend-up-right-fill" class="size-[18px]" />
      </span>
    </button>
  </div>
</template>
