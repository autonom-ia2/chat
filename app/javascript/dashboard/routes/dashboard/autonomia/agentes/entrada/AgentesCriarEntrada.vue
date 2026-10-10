<script setup>
import { defineAsyncComponent } from 'vue';
import AgentBuilderPage from '../../pages/AgentBuilderPage.vue';
import { useJornadaAtiva } from '../composables/useJornadaAtiva';

// #1181 (DECISOES.md item 1) — seletor da rota autonomia_agents_builder (mesmo nome, caminho, meta e
// guarda). Flag desligada: o Construtor antigo, importado de forma estática, então continua um pedaço
// só e nenhuma chamada nova de API. Flag ligada: a criação nova (Conte · Confira · Comece), carregada
// à parte. A decisão é tomada uma vez no setup (não reativa): se a conta mudar na store no meio do
// uso, o Construtor antigo não é desmontado (desmontar dispara o fechamento forçado no servidor).
const AgenteCriarPage = defineAsyncComponent(
  () => import('../pages/AgenteCriarPage.vue')
);

const jornadaAtiva = useJornadaAtiva();
</script>

<template>
  <AgenteCriarPage v-if="jornadaAtiva" />
  <AgentBuilderPage v-else />
</template>
