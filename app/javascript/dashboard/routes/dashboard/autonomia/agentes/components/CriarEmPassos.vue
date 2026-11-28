<script setup>
import { computed, nextTick, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { isNavigationFailure, useRoute, useRouter } from 'vue-router';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import { useCanManage } from 'dashboard/composables/useCanManage';
import AgentesHeroi from './AgentesHeroi.vue';
import AgenteErro from './AgenteErro.vue';
import EscolhaDoPapel from './EscolhaDoPapel.vue';
import ComoComecar from './ComoComecar.vue';
import PapelEscolhido from './PapelEscolhido.vue';
import { useFase2 } from '../composables/useFase2';
import { useAgenteIaPorCaixa } from '../composables/useAgenteIaPorCaixa';
import { useRamosDeSeguro } from '../composables/useRamosDeSeguro';
import { useContratados } from '../composables/useContratados';
import { MODELOS } from '../constants/modelos';
import { MODELOS_CONTRATADOS } from '../constants/contratados';
import { principaisPossiveis } from '../utils/ajudante';
import {
  JEITO,
  PAPEL,
  papeisDisponiveis,
  papelDoPasso,
  queryDeConversar,
  queryDeEscrever,
  queryDoPapel,
  temPasso2,
} from '../constants/papeis';

// #3219 — "Criar agente" em dois passos, no herói navy: 1. o que ele vai fazer (EscolhaDoPapel); 2. como começar
// (ComoComecar), com o papel escolhido no topo e "Trocar" para voltar ao passo 1.
// Serve à página "Criar agente" (rota autonomia_agents_builder) e à tela inicial de Agentes sem agentes (`inicio`:
// mantém a pergunta forte do herói T01, com subtítulo próprio, e o cartão de atender clientes traz os balões de
// exemplo). O passo 2 mora num lugar só, a página "Criar agente": escolher um papel com passo 2 abre
// `autonomia_agents_builder?papel=<papel>` (da tela inicial também). Escolher entra no histórico, então o "voltar" do
// navegador vira "Trocar"; na troca de passo, o foco vai para o título.
// Papel sem passo 2 (agente da equipe, ajudante, conectar) e a escolha final abrem a criação na mesma rota; antes,
// avisam quem usa (`escolher`, com a query). Se a abertura falhar, o aviso aparece com "Tentar de novo" e nada fica
// travado em "Começando…".
// O ajudante só aparece quando a conta tem um agente que ele pode ajudar (a regra do passo "quem ele ajuda": fala com
// o cliente e não é rascunho). Fora da tela inicial (que já sabe que não há agente), a página lê a lista ao abrir e,
// até ela chegar, o passo 1 mostra um esqueleto, para os cartões não pularem. Se a lista não vier, o cartão fica como
// era antes desta tela (só com a Fase 2) e a criação decide.
// Conta sem canal: o aviso fica no passo 2 de atender clientes, o único papel que precisa de canal.
// #3211 — os agentes prontos para contratar ("Vendem sozinhos") vêm do servidor (useContratados) e aparecem no passo
// 2 de atender clientes; a tela só mostra os modelos que conhece (MODELOS_CONTRATADOS).
const props = defineProps({
  inicio: { type: Boolean, default: false },
});

const emit = defineEmits(['escolher']);

const { t } = useI18n();
const route = useRoute();
const router = useRouter();
const store = useStore();
const NS = 'AGENTS.JORNADA.CRIAR_EM_PASSOS';
const ROTA = 'autonomia_agents_builder';
const podeGerenciar = useCanManage('autonomia_manage');
const fase2 = useFase2();
const porCaixa = useAgenteIaPorCaixa();
const agentes = useMapGetter('autonomiaAgents/getRecords');
const caixas = useMapGetter('inboxes/getInboxes');
const { ramos } = useRamosDeSeguro();
const { modelos: liberados, planos: planosContratados } = useContratados();
const contratados = computed(() =>
  liberados.value.filter(modelo => MODELOS_CONTRATADOS.includes(modelo))
);

const comecando = ref(null);
const falhou = ref(null);
const heroi = ref(null);
const agentesLidos = ref(props.inicio || !!agentes.value?.length);
const listaFalhou = ref(false);
let ultimaEscolha = null;

const papeis = computed(() =>
  papeisDisponiveis({
    fase2: fase2.value,
    porCaixa: porCaixa.value,
    temQuemAjudar:
      !props.inicio &&
      (listaFalhou.value || principaisPossiveis(agentes.value).length > 0),
  })
);
const papel = computed(() => (props.inicio ? null : papelDoPasso(route.query)));
const atender = computed(() => papel.value === PAPEL.ATENDER);
const semCanal = computed(() => atender.value && !(caixas.value || []).length);

const exemplo = computed(() => {
  const [modelo] = MODELOS;
  const base = `AGENTS.JORNADA.MODELOS.${modelo.i18n}`;
  return [
    { de: 'cliente', texto: t(`${base}.CLIENTE`), hora: modelo.horario },
    { de: 'agente', texto: t(`${base}.AGENTE`), hora: modelo.horario },
  ];
});

const titulo = computed(() => {
  if (papel.value) return t(`${NS}.COMO.TITULO`);
  return t(props.inicio ? 'AGENTS.JORNADA.HEROI.TITULO' : `${NS}.PAPEL.TITULO`);
});
const texto = computed(() => {
  if (!podeGerenciar.value) return t('AGENTS.JORNADA.HEROI.SO_VER');
  if (!papel.value) {
    return t(props.inicio ? `${NS}.PAPEL.TEXTO_INICIO` : `${NS}.PAPEL.TEXTO`);
  }
  if (!atender.value) return t(`${NS}.COMO.TEXTO_OUTROS`);
  return t(
    ramos.value.length ? `${NS}.COMO.TEXTO_RAMOS` : `${NS}.COMO.TEXTO_ATENDER`
  );
});

watch(papel, async () => {
  falhou.value = null;
  await nextTick();
  heroi.value?.$el?.querySelector('h1')?.focus();
});

onMounted(async () => {
  if (props.inicio) return;
  try {
    await store.dispatch('autonomiaAgents/get');
  } catch {
    listaFalhou.value = true;
  } finally {
    agentesLidos.value = true;
  }
});

const abrir = async (chave, query) => {
  if (comecando.value) return;
  ultimaEscolha = { chave, query };
  comecando.value = chave;
  falhou.value = null;
  emit('escolher', query);
  try {
    const resultado = await router.push({ name: ROTA, query });
    if (isNavigationFailure(resultado)) falhou.value = chave;
  } catch {
    falhou.value = chave;
  } finally {
    comecando.value = null;
  }
};

// Papel com passo 2 só troca a consulta (sem avisar `escolher`); a falha mostra o mesmo aviso da escolha final.
const irParaPasso2 = async chave => {
  ultimaEscolha = { chave, query: queryDoPapel(chave), passo2: true };
  falhou.value = null;
  try {
    const resultado = await router.push({
      name: ROTA,
      query: queryDoPapel(chave),
    });
    if (isNavigationFailure(resultado)) falhou.value = chave;
  } catch {
    falhou.value = chave;
  }
};

const escolherPapel = chave => {
  if (temPasso2(chave)) {
    irParaPasso2(chave);
    return;
  }
  abrir(chave, queryDoPapel(chave));
};

const trocar = () => {
  if (!comecando.value) router.push({ name: ROTA, query: {} });
};

const abrirContratado = modelo => {
  if (!comecando.value) {
    router.push({ name: 'autonomia_contratado_modelo', params: { modelo } });
  }
};
const usarRamo = chave => abrir(chave, { ramo: chave });
const usarModelo = chave => abrir(chave, { modelo: chave });
const usarOpcao = chave =>
  abrir(
    chave,
    chave === JEITO.ESCREVER
      ? queryDeEscrever(papel.value)
      : queryDeConversar(papel.value)
  );
const tentarDeNovo = () => {
  if (!ultimaEscolha) return;
  if (ultimaEscolha.passo2) irParaPasso2(ultimaEscolha.chave);
  else abrir(ultimaEscolha.chave, ultimaEscolha.query);
};
</script>

<template>
  <AgentesHeroi
    ref="heroi"
    data-criar-em-passos
    :data-passo="papel ? 2 : 1"
    :titulo="titulo"
    :texto="texto"
  >
    <template v-if="papel" #topo>
      <PapelEscolhido
        :papel="papel"
        :desligado="!!comecando"
        class="mb-2"
        @trocar="trocar"
      />
    </template>
    <ComoComecar
      v-if="papel"
      :papel="papel"
      :ramos="ramos"
      :pode-usar="podeGerenciar"
      :comecando="comecando"
      :falhou="!!falhou"
      :sem-canal="semCanal"
      :contratados="contratados"
      :planos-contratados="planosContratados"
      @usar-ramo="usarRamo"
      @usar-modelo="usarModelo"
      @usar-opcao="usarOpcao"
      @tentar-de-novo="tentarDeNovo"
      @abrir-contratado="abrirContratado"
    />
    <div
      v-else-if="!agentesLidos"
      data-esqueleto-papeis
      aria-hidden="true"
      class="flex flex-col gap-6"
    >
      <span class="h-40 rounded-2xl bg-white/10 motion-safe:animate-pulse" />
      <span class="grid grid-cols-1 gap-3 md:grid-cols-2">
        <span class="h-32 rounded-2xl bg-white/10 motion-safe:animate-pulse" />
        <span class="h-32 rounded-2xl bg-white/10 motion-safe:animate-pulse" />
      </span>
    </div>
    <template v-else>
      <EscolhaDoPapel
        :papeis="papeis"
        :pode-usar="podeGerenciar"
        :exemplo="inicio ? exemplo : []"
        @escolher="escolherPapel"
      />
      <AgenteErro
        v-if="falhou"
        data-erro-ao-comecar
        :titulo="t(`${NS}.COMO.ERRO`)"
        :acao="t('AGENTS.JORNADA.COMUM.TENTAR_DE_NOVO')"
        :carregando="!!comecando"
        @acao="tentarDeNovo"
      />
    </template>
  </AgentesHeroi>
</template>
