<script setup>
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import Segmento from './Segmento.vue';

// #2226 v2 — a escolha no canto de um cartão: até 3 opções, segmento (tudo à vista); mais que
// isso, a escolha do produto (ChoiceSelect), para nunca passar da borda do cartão.
defineProps({
  // [{ value, label }]
  opcoes: { type: Array, required: true },
  rotulo: { type: String, required: true },
});

const escolhida = defineModel({ type: String, required: true });
const MAXIMO_NO_SEGMENTO = 3;
</script>

<template>
  <Segmento
    v-if="opcoes.length <= MAXIMO_NO_SEGMENTO"
    v-model="escolhida"
    :opcoes="opcoes"
    :rotulo="rotulo"
  />
  <ChoiceSelect
    v-else
    v-model="escolhida"
    data-escolha-do-cartao
    compact
    :options="opcoes"
    :aria-label="rotulo"
  />
</template>
