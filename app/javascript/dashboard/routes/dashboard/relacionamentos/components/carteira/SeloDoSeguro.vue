<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import SeloDeEstado from '../comum/SeloDeEstado.vue';
import { diasParaTerminar, seloDoSeguro } from '../../fonte/selosDoSeguro';
import { chaveDoSelo, tomDoSelo } from '../../carteira/tomDoSelo';

// #2897 — o selo de um seguro: Ativo, Vencido ou Cancelado. A cor e o texto
// saem de uma regra só (carteira/tomDoSelo.js): o ativo que vence logo fica em
// âmbar.
const props = defineProps({
  seguro: { type: Object, required: true },
  agora: { type: Number, default: () => Date.now() },
});

const { t } = useI18n();
const selo = computed(() => seloDoSeguro(props.seguro, props.agora));
const tom = computed(() =>
  tomDoSelo(selo.value, diasParaTerminar(props.seguro, props.agora))
);
</script>

<template>
  <SeloDeEstado data-carteira="selo" :tom="tom" :data-selo-da-carteira="selo">
    {{ t(chaveDoSelo(selo)) }}
  </SeloDeEstado>
</template>
