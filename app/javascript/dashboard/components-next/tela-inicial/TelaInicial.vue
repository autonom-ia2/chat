<script setup>
import { computed, reactive } from 'vue';
import { useRoute } from 'vue-router';
import TelaInicialSaudacao from './TelaInicialSaudacao.vue';
import TelaInicialResumo from './TelaInicialResumo.vue';
import TelaInicialMarca from './TelaInicialMarca.vue';
import { opcaoDaTela } from './telaInicial';
import { useTelaInicial } from './useTelaInicial';

// #1801 — a opção em teste vem da URL (?inicio=1|2|3); o EmptyState só monta esta tela
// quando há opção.
const OPCOES = {
  1: TelaInicialSaudacao,
  2: TelaInicialResumo,
  3: TelaInicialMarca,
};

const route = useRoute();
const opcao = computed(() => opcaoDaTela(route.query));
const dados = reactive(useTelaInicial());
</script>

<template>
  <component :is="OPCOES[opcao]" v-if="opcao" :dados="dados" />
</template>
