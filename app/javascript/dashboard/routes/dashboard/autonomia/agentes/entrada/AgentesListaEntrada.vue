<script setup>
import { defineAsyncComponent } from 'vue';
import AgentsHubPage from '../../pages/AgentsHubPage.vue';
import { useJornadaAtiva } from '../composables/useJornadaAtiva';

// #1181 (DECISOES.md item 1) — seletor da rota autonomia_agents_index (mesmo nome, caminho, meta e
// guarda). Flag desligada: a lista antiga, importada de forma estática, então continua um pedaço só
// e nenhuma chamada nova de API. Flag ligada: a lista nova, carregada à parte. A decisão é tomada
// uma vez no setup (não reativa): uma atualização da conta na store não troca a tela no meio do uso.
const AgentesListaPage = defineAsyncComponent(
  () => import('../pages/AgentesListaPage.vue')
);

const jornadaAtiva = useJornadaAtiva();
</script>

<template>
  <AgentesListaPage v-if="jornadaAtiva" />
  <AgentsHubPage v-else />
</template>
