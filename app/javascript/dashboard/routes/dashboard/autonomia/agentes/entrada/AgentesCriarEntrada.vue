<script setup>
import { defineAsyncComponent, ref, watch } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import AgentBuilderPage from '../../pages/AgentBuilderPage.vue';
import { useJornadaAtiva } from '../composables/useJornadaAtiva';
import { usePrototipoFase2 } from '../prototipo/usePrototipoFase2';

// #1181 (DECISOES.md item 1) — seletor da rota autonomia_agents_builder (mesmo nome, caminho, meta e
// guarda). Flag desligada: o Construtor antigo, importado de forma estática, então continua um pedaço
// só e nenhuma chamada nova de API. Flag ligada: a criação nova (Conte · Confira · Comece), carregada
// à parte. A decisão é tomada uma vez no setup (não reativa): se a conta mudar na store no meio do
// uso, o Construtor antigo não é desmontado (desmontar dispara o fechamento forçado no servidor).
// #1366 (protótipo da Fase 2, rodada 3): sem modelo, rascunho nem tipo na URL, abre primeiro a página
// "Criar agente" (escolha do modelo ou de outro tipo). A criação só monta depois da escolha, porque
// ela lê a URL uma vez, ao montar.
const AgenteCriarPage = defineAsyncComponent(
  () => import('../pages/AgenteCriarPage.vue')
);
const AgenteEscolherPage = defineAsyncComponent(
  () => import('../pages/AgenteEscolherPage.vue')
);

const jornadaAtiva = useJornadaAtiva();
// Sem o protótipo, nada de rota nem roteador aqui: o seletor continua como antes.
const prototipo = jornadaAtiva && usePrototipoFase2();
const route = prototipo ? useRoute() : null;
const router = prototipo ? useRouter() : null;

const semEscolha = query =>
  !query.modelo && !query.type && !query.agente && !query.tipo;
const escolhendo = ref(prototipo && semEscolha(route.query));

if (prototipo) {
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
