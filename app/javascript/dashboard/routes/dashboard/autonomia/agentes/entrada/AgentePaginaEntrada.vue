<script setup>
import { computed, defineAsyncComponent } from 'vue';
import { useRoute } from 'vue-router';
import AgentPanelPage from '../../pages/AgentPanelPage.vue';
import { useJornadaAtiva } from '../composables/useJornadaAtiva';
import { gavetaDaAba } from '../utils/pagina';

// #1181 (DECISOES.md item 1) — seletor da rota autonomia_agent_panel (mesmo nome, caminho, meta,
// guarda e `props`). Flag desligada: o painel antigo, importado de forma estática, recebe
// exatamente {agentId, tab} como antes (o tab padrão 'test' vem da própria rota). Flag ligada: a
// página nova, carregada à parte, com o :tab antigo traduzido para a gaveta. Só o :tab escrito na
// URL abre gaveta; o 'test' padrão da rota não abre nada. A escolha da página é feita uma vez no
// setup (não reativa); a gaveta acompanha a URL. O router-view do painel só tem key por conta, então
// ir de um agente a outro reaproveitaria a página: a key pelo agentId remonta a página nova inteira
// (leituras, gaveta e conversa de mudar). O painel antigo trata a troca sozinho e fica como estava.
const props = defineProps({
  agentId: { type: [String, Number], required: true },
  tab: { type: String, default: 'test' },
});

const AgentePage = defineAsyncComponent(
  () => import('../pages/AgentePage.vue')
);

const jornadaAtiva = useJornadaAtiva();
const route = useRoute();

const gaveta = computed(() =>
  jornadaAtiva ? gavetaDaAba(route.params.tab) : null
);
</script>

<template>
  <AgentePage
    v-if="jornadaAtiva"
    :key="agentId"
    :agent-id="agentId"
    :gaveta="gaveta"
  />
  <AgentPanelPage v-else :agent-id="props.agentId" :tab="props.tab" />
</template>
