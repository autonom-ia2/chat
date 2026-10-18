<script setup>
// Aviso "N mensagens não lidas" (#1702): fica antes da 1ª mensagem do cliente que
// ninguém leu, com o número exato. Só o selo, no verde do app, sem a faixa de ponta a
// ponta: no escuro ela virava um bloco preto sobre o papel de parede (pedido do Rodrigo, 18/10).
import { useI18n } from 'vue-i18n';
import { CLASSES_DO_SEPARADOR_DE_DIA } from './visualWhatsapp';

defineProps({
  quantidade: { type: Number, required: true },
});

const { t } = useI18n();
</script>

<template>
  <li class="list-none my-3 flex justify-center" data-faixa-nao-lidas>
    <span
      :class="CLASSES_DO_SEPARADOR_DE_DIA"
      class="!text-[#008069] dark:!text-[#21C063] font-medium"
    >
      {{ t('CONVERSA_CANAL.ROLAGEM.NAO_LIDAS', { n: quantidade }, quantidade) }}
    </span>
  </li>
</template>
