<script setup>
import { computed, defineAsyncComponent, ref } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import AgentBuilderPage from '../../pages/AgentBuilderPage.vue';
import { useJornadaAtiva } from '../composables/useJornadaAtiva';
import { useAgenteIaPorCaixaNaEntrada } from '../composables/useAgenteIaPorCaixa';

// #1181 (DECISOES.md item 1) — seletor da rota autonomia_agents_builder (mesmo nome, caminho, meta e
// guarda). Flag desligada: o Construtor antigo, importado de forma estática, então continua um pedaço
// só e nenhuma chamada nova de API. Flag ligada: a criação nova (Conte · Confira · Comece), carregada
// à parte. A decisão é tomada uma vez no setup (não reativa): se a conta mudar na store no meio do
// uso, o Construtor antigo não é desmontado (desmontar dispara o fechamento forçado no servidor).
// #1543: com a flag ligada e sem modelo, rascunho nem atuação na URL, abre primeiro a página
// "Criar agente" (escolha do modelo ou do Copiloto da equipe). A escolha entra no histórico (push):
// a criação só monta depois dela, porque lê a URL uma vez, ao montar, e o "Voltar" do navegador na
// criação devolve a URL sem escolha, que mostra a página de novo.
// #1433: `?papel=area` (agente da equipe) também é uma escolha.
const AgenteCriarPage = defineAsyncComponent(
  () => import('../pages/AgenteCriarPage.vue')
);
const AgenteEscolherPage = defineAsyncComponent(
  () => import('../pages/AgenteEscolherPage.vue')
);
// #1648 — `?conectar=outro`: conectar agente de outro sistema, em página inteira. Só com a aba
// "Agente de IA" por caixa ligada na conta.
const AgenteConectarPage = defineAsyncComponent(
  () => import('../pages/AgenteConectarPage.vue')
);

const jornadaAtiva = useJornadaAtiva();
const porCaixa = useAgenteIaPorCaixaNaEntrada();
// Flag desligada: nada de rota nem roteador aqui, o seletor continua como antes.
const route = jornadaAtiva ? useRoute() : null;
const router = jornadaAtiva ? useRouter() : null;

const semEscolha = query =>
  !query.modelo &&
  !query.type &&
  !query.agente &&
  !query.atuacao &&
  !query.papel &&
  !(porCaixa && query.conectar);
const conectando = computed(
  () => jornadaAtiva && porCaixa && route.query.conectar === 'outro'
);
const escolhendo = computed(() => jornadaAtiva && semEscolha(route.query));
const veioDaEscolha = ref(false);

const escolher = async query => {
  veioDaEscolha.value = true;
  await router.push({ query });
};
</script>

<template>
  <AgenteConectarPage v-if="conectando" />
  <AgenteEscolherPage v-else-if="escolhendo" @escolher="escolher" />
  <AgenteCriarPage v-else-if="jornadaAtiva" :focar-titulo="veioDaEscolha" />
  <AgentBuilderPage v-else />
</template>
