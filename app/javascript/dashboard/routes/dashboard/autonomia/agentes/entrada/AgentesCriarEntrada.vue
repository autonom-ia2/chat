<script setup>
import { defineAsyncComponent, ref, watch } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import AgentBuilderPage from '../../pages/AgentBuilderPage.vue';
import { useJornadaAtiva } from '../composables/useJornadaAtiva';

// #1181 (DECISOES.md item 1) — seletor da rota autonomia_agents_builder (mesmo nome, caminho, meta e
// guarda). Flag desligada: o Construtor antigo, importado de forma estática, então continua um pedaço
// só e nenhuma chamada nova de API. Flag ligada: a criação nova (Conte · Confira · Comece), carregada
// à parte. A decisão é tomada uma vez no setup (não reativa): se a conta mudar na store no meio do
// uso, o Construtor antigo não é desmontado (desmontar dispara o fechamento forçado no servidor).
// #1543: com a flag ligada e sem modelo, rascunho nem atuação na URL, abre primeiro a página
// "Criar agente" (escolha do modelo ou do Copiloto da equipe). A criação só monta depois da escolha,
// porque ela lê a URL uma vez, ao montar.
const AgenteCriarPage = defineAsyncComponent(
  () => import('../pages/AgenteCriarPage.vue')
);
const AgenteEscolherPage = defineAsyncComponent(
  () => import('../pages/AgenteEscolherPage.vue')
);

const jornadaAtiva = useJornadaAtiva();
// Flag desligada: nada de rota nem roteador aqui, o seletor continua como antes.
const route = jornadaAtiva ? useRoute() : null;
const router = jornadaAtiva ? useRouter() : null;

const semEscolha = query =>
  !query.modelo && !query.type && !query.agente && !query.atuacao;
const escolhendo = ref(jornadaAtiva && semEscolha(route.query));

// "Criar agente" no menu com a criação aberta (mesma rota, sem query) volta para a escolha.
if (jornadaAtiva) {
  watch(
    () => route.query,
    query => {
      if (semEscolha(query)) escolhendo.value = true;
    }
  );
}

const escolher = async query => {
  await router.replace({ query });
  escolhendo.value = false;
};
</script>

<template>
  <AgenteEscolherPage v-if="escolhendo" @escolher="escolher" />
  <AgenteCriarPage v-else-if="jornadaAtiva" />
  <AgentBuilderPage v-else />
</template>
