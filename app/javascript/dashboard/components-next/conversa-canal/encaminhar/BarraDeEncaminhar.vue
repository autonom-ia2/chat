<script setup>
// A barra do modo seleção (#1702), no lugar do campo de digitar, como no WhatsApp
// Web: "✕" para sair, "N selecionada(s)" e a seta de encaminhar à direita.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Icon from 'next/icon/Icon.vue';

const props = defineProps({
  quantidade: { type: Number, required: true },
});
const emit = defineEmits(['sair', 'encaminhar']);
const { t } = useI18n();

const vazia = computed(() => props.quantidade === 0);
</script>

<template>
  <div
    class="flex items-center gap-4 min-h-[60px] px-4 py-2 bg-white dark:bg-[#161717] border-t border-[#000]/[0.06] dark:border-white/[0.06] text-[#0A0A0A] dark:text-[#FAFAFA]"
    role="toolbar"
    :aria-label="t('CONVERSA_CANAL.ENCAMINHAR.ENVIAR_SELECAO')"
    data-barra-de-encaminhar
  >
    <button
      type="button"
      class="grid place-content-center size-11 rounded-full text-[#54656F] dark:text-[#AEBAC1] hover:bg-[#0A0A0A]/5 dark:hover:bg-white/5"
      :aria-label="t('CONVERSA_CANAL.ENCAMINHAR.SAIR')"
      @click="emit('sair')"
    >
      <Icon icon="i-ph-x" class="size-6" />
    </button>
    <span class="flex-1 text-[15px] leading-5" aria-live="polite">
      {{ t('CONVERSA_CANAL.ENCAMINHAR.SELECIONADAS', quantidade) }}
    </span>
    <button
      type="button"
      class="grid place-content-center size-11 rounded-full text-[#54656F] dark:text-[#AEBAC1] hover:bg-[#0A0A0A]/5 dark:hover:bg-white/5 disabled:opacity-40 disabled:cursor-not-allowed disabled:hover:bg-transparent"
      :disabled="vazia"
      :aria-label="t('CONVERSA_CANAL.ENCAMINHAR.ENVIAR_SELECAO')"
      data-encaminhar-selecionadas
      @click="emit('encaminhar')"
    >
      <Icon icon="i-ph-arrow-bend-up-right-fill" class="size-6" />
    </button>
  </div>
</template>
