<script setup>
// Figurinha com a cara do WhatsApp (#1702): solta, sem balão nem fundo, 190 px como no
// WhatsApp Web. A animada (WebP animado) anima sozinha. A hora fica num selo pequeno
// sobre o canto de baixo (classesDaHora em visualWhatsapp.js). O espaço fica reservado
// enquanto o arquivo carrega, para a conversa não pular.
import { useI18n } from 'vue-i18n';

defineProps({
  attachment: { type: Object, required: true },
  carregada: { type: Boolean, default: false },
});

const emit = defineEmits(['error']);

const { t } = useI18n();
</script>

<template>
  <div class="size-[190px] max-w-full" data-figurinha-do-whatsapp>
    <img
      v-if="carregada"
      class="block size-full object-contain skip-context-menu"
      :src="attachment.dataUrl"
      :alt="t('CONVERSA_CANAL.MIDIA.FIGURINHA')"
      @error="emit('error')"
    />
  </div>
</template>
