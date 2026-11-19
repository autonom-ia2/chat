<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import SeloDeEstado from '../comum/SeloDeEstado.vue';
import { diasParaTerminar, seloDoSeguro } from '../../fonte/selosDoSeguro';
import { chaveDoSelo, tomDoSelo } from '../../carteira/tomDoSelo';

// #2897 — o selo de um seguro: Ativo, Vencido ou Cancelado. A cor e o texto
// saem de uma regra só (carteira/tomDoSelo.js): o ativo que vence logo diz
// "Vence logo", em âmbar (#3057).
// #2898 — a renovação soma Em renovação (azul) e Renovado (verde). Os cinco
// chegam em todo lugar que mostra o selo: a aba Seguros, a ficha, o painel da
// conversa e a lista de pessoas.
// Na linha de um seguro o selo diz só "Vencido". Fora dela (a lista de pessoas)
// quem usa manda o texto inteiro em `rotulo` ("Seguro vencido"): sozinho, ao
// lado do nome de uma pessoa, "Vencido" não diz o quê.
// #2899 (E6.5) — o seguro que a pessoa tem em outra corretora ganha, ao lado,
// o selo neutro "De outra corretora", em todo lugar que mostra o selo.
const props = defineProps({
  seguro: { type: Object, required: true },
  agora: { type: Number, default: () => Date.now() },
  rotulo: { type: String, default: '' },
});

const { t } = useI18n();
const selo = computed(() => seloDoSeguro(props.seguro, props.agora));
const dias = computed(() => diasParaTerminar(props.seguro, props.agora));
const tom = computed(() => tomDoSelo(selo.value, dias.value));
</script>

<template>
  <SeloDeEstado data-carteira="selo" :tom="tom" :data-selo-da-carteira="selo">
    {{ rotulo || t(chaveDoSelo(selo, dias)) }}
  </SeloDeEstado>
  <SeloDeEstado v-if="seguro.deFora" data-carteira="selo-de-fora" tom="neutro">
    {{ t('RELACIONAMENTOS_CARTEIRA.SELOS.DE_FORA') }}
  </SeloDeEstado>
</template>
