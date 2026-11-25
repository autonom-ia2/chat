<script setup>
import { computed, defineAsyncComponent, ref } from 'vue';
import { useRoute } from 'vue-router';
import AgentBuilderPage from '../../pages/AgentBuilderPage.vue';
import { useJornadaAtiva } from '../composables/useJornadaAtiva';
import { useAgenteIaPorCaixaNaEntrada } from '../composables/useAgenteIaPorCaixa';
import { papelDoPasso } from '../constants/papeis';
import { useOcuparCantoDaBolinha } from 'dashboard/components/autonomia/guide/cantoDaBolinha';

// #1181 (DECISOES.md item 1) — seletor da rota autonomia_agents_builder (mesmo nome, caminho, meta e
// guarda). Flag desligada: o Construtor antigo, importado de forma estática, então continua um pedaço
// só e nenhuma chamada nova de API. Flag ligada: a criação nova (Conte · Confira · Comece), carregada
// à parte. A decisão é tomada uma vez no setup (não reativa): se a conta mudar na store no meio do
// uso, o Construtor antigo não é desmontado (desmontar dispara o fechamento forçado no servidor).
// #3219 — sem escolha na URL, abre "Criar agente" em dois passos (AgenteCriarEmPassosPage): sem query, o passo 1
// (o que ele vai fazer); com `?papel=atender|copiloto` sozinho, o passo 2 daquele papel (como começar). A criação
// só monta depois da escolha, porque lê a URL uma vez, ao montar; a escolha entra no histórico (push), e o "Voltar"
// do navegador na criação devolve a URL da escolha, que mostra os passos de novo.
// São escolha (abrem a criação): `?modelo=` (e o `?type=` dos links antigos), `?agente=` (rascunho a continuar),
// `?atuacao=interno` (Copiloto, #1494), `?papel=area` (agente da equipe, #1433), `?papel=ajudante` (tema 14),
// `?ramo=` (pronto por ramo de seguro, #2881). `?papel=atender|copiloto` sozinho é o passo 2, não a criação.
// `?escrever=1` (#3214) abre o escrever, com o papel de `?papel=` (#3219); `?conectar=outro` (#1648), o conectar.
const AgenteCriarPage = defineAsyncComponent(
  () => import('../pages/AgenteCriarPage.vue')
);
const AgenteCriarEmPassosPage = defineAsyncComponent(
  () => import('../pages/AgenteCriarEmPassosPage.vue')
);
// #1648 — `?conectar=outro`: conectar agente de outro sistema, em página inteira. Só com a aba
// "Agente de IA" por caixa ligada na conta.
const AgenteConectarPage = defineAsyncComponent(
  () => import('../pages/AgenteConectarPage.vue')
);
// #3214 — `?escrever=1`: criar o agente com as instruções que a pessoa já tem, em página inteira.
const AgenteEscreverPage = defineAsyncComponent(
  () => import('../pages/AgenteEscreverPage.vue')
);

const jornadaAtiva = useJornadaAtiva();
const porCaixa = useAgenteIaPorCaixaNaEntrada();
// Flag desligada: nada de rota nem roteador aqui, o seletor continua como antes.
const route = jornadaAtiva ? useRoute() : null;

// `?papel=` só é escolha quando é a marca de um papel da criação (area, ajudante); atender e copiloto são o passo 2.
const papelDaCriacao = query => !!query.papel && !papelDoPasso(query);
const semEscolha = query =>
  !query.modelo &&
  !query.type &&
  !query.agente &&
  !query.atuacao &&
  !papelDaCriacao(query) &&
  !query.ramo &&
  !query.escrever &&
  !(porCaixa && query.conectar);
const conectando = computed(
  () => jornadaAtiva && porCaixa && route.query.conectar === 'outro'
);
const escrevendo = computed(() => jornadaAtiva && !!route.query.escrever);
const papelDoEscrever = computed(() =>
  jornadaAtiva ? papelDoPasso(route.query) || '' : ''
);
const escolhendo = computed(() => jornadaAtiva && semEscolha(route.query));
const veioDaEscolha = ref(false);

// #3192 — a criação (nova ou o Construtor antigo) tem a caixa de envio do
// ajudante no canto da bolinha do Guia: no celular ela some. Na escolha, no
// conectar e no escrever (#3214) não há caixa, e a bolinha fica.
useOcuparCantoDaBolinha(
  computed(() => !conectando.value && !escolhendo.value && !escrevendo.value)
);

// Os passos abrem a criação sozinhos (e mostram o erro se ela não abrir); aqui só fica a marca de que a pessoa veio
// da escolha, para a criação levar o foco ao título.
const aoEscolher = () => {
  veioDaEscolha.value = true;
};
</script>

<template>
  <AgenteConectarPage v-if="conectando" />
  <AgenteEscreverPage v-else-if="escrevendo" :papel="papelDoEscrever" />
  <AgenteCriarEmPassosPage v-else-if="escolhendo" @escolher="aoEscolher" />
  <AgenteCriarPage v-else-if="jornadaAtiva" :focar-titulo="veioDaEscolha" />
  <AgentBuilderPage v-else />
</template>
