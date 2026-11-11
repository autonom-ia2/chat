<script setup>
import { computed } from 'vue';
import {
  SELO_PARCELA_ATRASADA,
  seloDoSeguro,
  temParcelaAtrasada,
} from '../../fonte/selosDoSeguro';
import SeloDaCarteira from './SeloDaCarteira.vue';

// #2897 — os selos de um seguro: o da situação (pela data de hoje) e, ao lado,
// "Parcela atrasada" quando há parcela em aberto.
const props = defineProps({
  seguro: { type: Object, required: true },
  agora: { type: Number, default: () => Date.now() },
});

const selo = computed(() => seloDoSeguro(props.seguro, props.agora));
</script>

<template>
  <SeloDaCarteira data-carteira="selo" :selo="selo" />
  <SeloDaCarteira
    v-if="temParcelaAtrasada(seguro)"
    data-carteira="selo-parcela"
    :selo="SELO_PARCELA_ATRASADA"
  />
</template>
