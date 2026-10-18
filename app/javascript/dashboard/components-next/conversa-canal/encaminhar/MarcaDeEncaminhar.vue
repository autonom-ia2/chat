<script setup>
// Modo seleção do encaminhar (#1702): a linha inteira da mensagem vira o alvo de
// marcar, com a caixinha à esquerda, como no WhatsApp Web. Cobre o balão para o
// clique marcar em vez de abrir foto, link ou menu. Espaço e Enter marcam.
import { useI18n } from 'vue-i18n';
import CaixinhaDoWhatsapp from './CaixinhaDoWhatsapp.vue';

defineProps({
  marcada: { type: Boolean, default: false },
});
const emit = defineEmits(['alternar']);
const { t } = useI18n();
</script>

<template>
  <button
    type="button"
    role="checkbox"
    class="absolute inset-0 z-[3] flex items-center ltr:pl-4 rtl:pr-4 cursor-pointer bg-transparent focus-visible:outline focus-visible:outline-2 focus-visible:-outline-offset-2 focus-visible:outline-[#00A884]"
    :aria-checked="marcada"
    :aria-label="t('CONVERSA_CANAL.ENCAMINHAR.MARCAR')"
    data-marca-de-encaminhar
    @click.stop="emit('alternar')"
    @contextmenu.prevent.stop
  >
    <CaixinhaDoWhatsapp :marcada="marcada" />
  </button>
</template>
