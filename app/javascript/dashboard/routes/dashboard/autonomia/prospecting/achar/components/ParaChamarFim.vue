<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import AcharPronto from './AcharPronto.vue';

// #2692 — o fim do dia da fila (v4, T5). Rodada 3: a mesma cara do Pronto
// (visto verde-água, uma frase e um botão) e a conta inteira da fila: as que
// foram para o funil, as que voltam amanhã e as que não servem.
// Rodada 4: alinhado no topo, logo abaixo do título; o botão vai para o rodapé
// fixo da página.
const props = defineProps({
  foram: { type: Number, required: true },
  voltam: { type: Number, default: 0 },
  naoServem: { type: Number, default: 0 },
});
const { t } = useI18n();

const NS = 'PROSPECTING_ACHAR.FILA.FIM';
const conta = computed(() => {
  const partes = [t(`${NS}.FORAM`, { n: props.foram }, props.foram)];
  if (props.voltam) {
    partes.push(t(`${NS}.VOLTAM`, { n: props.voltam }, props.voltam));
  }
  if (props.naoServem) {
    partes.push(t(`${NS}.NAO_SERVE`, { n: props.naoServem }, props.naoServem));
  }
  return partes.join(' ');
});
</script>

<template>
  <AcharPronto
    :titulo="$t(`${NS}.TITULO`)"
    :detalhes="[conta]"
    class="w-full"
    data-fim-da-fila
  />
</template>
