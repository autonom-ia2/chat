<script setup>
import SeloDaCarteira from './SeloDaCarteira.vue';

// #2897 — na lista de pessoas e de empresas: o selo do seguro que mais pede
// atenção (vencido, parcela atrasada, em renovação ou renovado). Quem só tem
// seguro ativo ou cancelado não ganha selo.
defineProps({
  resumo: { type: Object, required: true },
});
</script>

<template>
  <SeloDaCarteira data-carteira="selo-da-pessoa" :selo="resumo.selo" />
</template>
