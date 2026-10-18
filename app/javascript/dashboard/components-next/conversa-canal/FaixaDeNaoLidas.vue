<script setup>
// Faixa "N mensagens não lidas" de ponta a ponta (#1702), como no app: fica antes da
// 1ª mensagem do cliente que ninguém leu, com o número exato.
import { useI18n } from 'vue-i18n';
import { CLASSES_DO_SEPARADOR_DE_DIA } from './visualWhatsapp';

defineProps({
  quantidade: { type: Number, required: true },
});

const { t } = useI18n();
</script>

<template>
  <li
    class="list-none -mx-4 my-3 py-1.5 flex justify-center bg-white/50 dark:bg-[#000]/20"
    data-faixa-nao-lidas
  >
    <span :class="CLASSES_DO_SEPARADOR_DE_DIA">
      {{ t('CONVERSA_CANAL.ROLAGEM.NAO_LIDAS', { n: quantidade }, quantidade) }}
    </span>
  </li>
</template>
