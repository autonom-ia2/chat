<script setup>
import { computed, onBeforeUnmount, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { useCanManage } from 'dashboard/composables/useCanManage';
import { useNumerosDaSemana } from '../composables/useNumerosDaSemana';
import { useCanaisOcupados } from '../composables/useCanaisOcupados';
import { usePermissoesDaJornada } from '../composables/usePermissoesDaJornada';
import {
  ESTADO,
  canaisDoAgente,
  contarEstados,
  estadoDoAgente,
  ordenarAgentes,
} from '../utils/estadoDoAgente';
import { fotoDoAgente } from '../utils/fotoDoCanal';
import { caixasDaEquipe } from '../utils/ondeTrabalha';
import { MODELOS, MODELO_DO_MEU_JEITO } from '../constants/modelos';
import { ATUACAO_INTERNA_NA_QUERY } from '../constants/criacao';
import AgentesHeroi from '../components/AgentesHeroi.vue';
import AgenteCartao from '../components/AgenteCartao.vue';
import ModeloCartao from '../components/ModeloCartao.vue';
import AgenteBotao from '../components/AgenteBotao.vue';
import AgenteErro from '../components/AgenteErro.vue';
import AgenteConfirmacao from '../components/AgenteConfirmacao.vue';
import AgenteOutroSistemaCartao from '../components/AgenteOutroSistemaCartao.vue';

// #1181 — lista nova de Agentes (protótipo T01 e T02), atrás da flag autonomia_agents_journey.
// T01 (nenhum agente): herói navy com a pergunta, os três modelos e "Do meu jeito".
// T02 (com agentes): herói compacto com a contagem e os cartões na ordem Atendendo → Parado →
// Cotação → Falta terminar. Números da semana (L1) e nomes dos canais (L2) chegam em paralelo e,
// se falharem, o cartão só perde a linha correspondente. Quem só vê não tem ação de escrita.
// "Usar este" e "Do meu jeito" vão ao Construtor com ?modelo=; "Continuar" leva ?agente= (PR2).
// #1494 — "Copiloto da equipe", abaixo de "Do meu jeito" no herói T01, vai com ?atuacao=interno: o
// agente ajuda a equipe dentro das conversas e nunca fala com cliente.
// #1543 — com agentes, "Criar agente" (herói e barra do celular) e "Ver modelos prontos" abrem a
// página inteira "Criar agente" (AgenteEscolherPage, na rota do Construtor sem query), no lugar
// da gaveta.
// #1369 — os cartões só aparecem quando a L1 e a L2 já responderam (ou falharam). Antes, eles
// surgiam com a lista e cresciam depois: a linha da semana e o nome do canal chegavam e empurravam
// para baixo os cartões seguintes — o rascunho fica por último —, e o primeiro clique em
// "Continuar" ou no "⋯" caía onde o botão estava um instante antes. A espera tem teto (2,5 s):
// se uma das leituras travar, os cartões aparecem assim mesmo e se completam quando ela chegar.
const { t } = useI18n();
const store = useStore();
const router = useRouter();
const podeGerenciar = useCanManage('autonomia_manage');
const { podeConectarCanal } = usePermissoesDaJornada();
const semana = useNumerosDaSemana();
const ocupacao = useCanaisOcupados();

const agentes = useMapGetter('autonomiaAgents/getRecords');
const caixas = useMapGetter('inboxes/getInboxes');
// #1648 (mockup-2) — agentes de outro sistema (agent_bot webhook) na mesma lista, sem seção à parte.
const outrosSistemas = useMapGetter('agentBots/getBots');

const carregando = ref(true);
const falhou = ref(false);
const comecandoModelo = ref(null);
const modeloQueFalhou = ref(null);
const confirmacao = ref(null);
const pendenteExcluir = ref(null);
const excluindo = ref(false);
const continuando = ref(null);
const esperaVencida = ref(false);

const ESPERA_ANTES_DE_REPETIR_MS = 1500;
const ESQUELETOS = 3;
const ESPERA_MAXIMA_DAS_LEITURAS_MS = 2500;
const ESPERA_MAXIMA_DO_CONSTRUTOR_MS = 8000;
let relogioDasLeituras = null;
let relogioDoConstrutor = null;
let tentativaDeContinuar = 0;

// Caixas em que o agente de outro sistema atende primeiro (L2; `agent_bot_id` é proposta do mockup).
const canaisDoOutro = bot =>
  ocupacao.estado.value === 'pronto'
    ? ocupacao.canais.value
        .filter(
          canal =>
            canal.occupied_by?.kind === 'external' &&
            canal.occupied_by.agent_bot_id === bot.id
        )
        .map(canal => canal.name)
    : null;
const outrosAtendendo = computed(() =>
  (outrosSistemas.value || []).filter(bot => canaisDoOutro(bot)?.length)
);
const outrosParados = computed(() =>
  (outrosSistemas.value || []).filter(bot => !canaisDoOutro(bot)?.length)
);
// Uma lista só, na ordem de sempre: quem atende (da plataforma e de outro sistema), na equipe,
// parados, cotação e rascunho.
const ULTIMOS = [ESTADO.COTACAO, ESTADO.FALTA_TERMINAR];
const lista = computed(() => {
  const ordenados = ordenarAgentes(agentes.value).map(agente => ({
    tipo: 'plataforma',
    agente,
    estado: estadoDoAgente(agente),
  }));
  const outro = agente => ({ tipo: 'outro', agente });
  return [
    ...ordenados.filter(item => item.estado === ESTADO.ATENDENDO),
    ...outrosAtendendo.value.map(outro),
    ...ordenados.filter(
      item => item.estado !== ESTADO.ATENDENDO && !ULTIMOS.includes(item.estado)
    ),
    ...outrosParados.value.map(outro),
    ...ordenados.filter(item => ULTIMOS.includes(item.estado)),
  ];
});
const contagem = computed(() => {
  const daPlataforma = contarEstados(agentes.value);
  return {
    ...daPlataforma,
    atendendo: daPlataforma.atendendo + outrosAtendendo.value.length,
    parados: daPlataforma.parados + outrosParados.value.length,
  };
});
const vazia = computed(
  () =>
    !carregando.value &&
    !falhou.value &&
    !agentes.value.length &&
    !(outrosSistemas.value || []).length
);
const leiturasDosCartoes = computed(
  () =>
    esperaVencida.value ||
    (semana.estado.value !== 'carregando' &&
      ocupacao.estado.value !== 'carregando')
);
// Esqueleto até a lista chegar e, com agentes, até os cartões terem tudo o que mostram.
const esperando = computed(
  () =>
    carregando.value ||
    (!falhou.value && !vazia.value && !leiturasDosCartoes.value)
);
const semCanal = computed(() => !(caixas.value || []).length);

// #1433: "N na equipe" só aparece quando há agente da equipe; tema 14 (#1434): "N ajudando", só com ajudante.
const contagemTexto = computed(() => {
  const { atendendo, naEquipe, ajudando, parados } = contagem.value;
  return [
    t('AGENTS.JORNADA.LISTA.CONTAGEM_ATENDENDO', { n: atendendo }, atendendo),
    naEquipe
      ? t('AGENTS.JORNADA.LISTA.CONTAGEM_NA_EQUIPE', { n: naEquipe }, naEquipe)
      : '',
    ajudando
      ? t('AGENTS.JORNADA.LISTA.CONTAGEM_AJUDANDO', { n: ajudando }, ajudando)
      : '',
    t('AGENTS.JORNADA.LISTA.CONTAGEM_PARADOS', { n: parados }, parados),
  ]
    .filter(Boolean)
    .join(' · ');
});

const linkConectarCanal = computed(
  () => router.resolve({ name: 'settings_inbox_new' }).href
);

// Mesma tolerância da lista antiga: uma falha passageira (deploy, 502) tenta de novo uma vez antes
// de mostrar o erro.
const esperar = ms =>
  new Promise(resolve => {
    setTimeout(resolve, ms);
  });

const carregar = async ({ repetir = true } = {}) => {
  carregando.value = true;
  falhou.value = false;
  try {
    await store.dispatch('autonomiaAgents/get');
    carregando.value = false;
  } catch {
    if (repetir) {
      await esperar(ESPERA_ANTES_DE_REPETIR_MS);
      await carregar({ repetir: false });
      return;
    }
    carregando.value = false;
    falhou.value = true;
  }
};

const tentarDeNovo = () => {
  carregar({ repetir: false });
  semana.carregar();
  ocupacao.carregar();
};

const COPILOTO = 'copiloto';

const abrirCriacao = async (chave, query) => {
  if (comecandoModelo.value) return;
  comecandoModelo.value = chave;
  modeloQueFalhou.value = null;
  try {
    await router.push({ name: 'autonomia_agents_builder', query });
  } catch {
    modeloQueFalhou.value = chave;
  } finally {
    comecandoModelo.value = null;
  }
};

const usarModelo = chave => abrirCriacao(chave, { modelo: chave });
const usarCopiloto = () =>
  abrirCriacao(COPILOTO, { atuacao: ATUACAO_INTERNA_NA_QUERY });

const abrirPaginaCriar = () =>
  router.push({ name: 'autonomia_agents_builder' });

const abrirAgente = agente =>
  router.push({
    name: 'autonomia_agent_panel',
    params: { agentId: agente.id },
  });

// #1525 — a cotação abre a página do agente, e não o módulo: de lá o "Abrir o agente" voltava para cá, e a
// corretora não achava onde pôr a Lia num canal. Sem canal, já na escolha de canal (o `:tab` channels, o fluxo da
// própria página); com canal, só a página.
const rotaDaCotacao = agente => ({
  name: 'autonomia_agent_panel',
  params:
    agente.tem_onde_trabalhar === false
      ? { agentId: agente.id, tab: 'channels' }
      : { agentId: agente.id },
});

const abrirCotacao = agente => router.push(rotaDaCotacao(agente));

// O Construtor é carregado à parte: enquanto ele chega, o botão mostra que está indo (um clique só).
// Se a navegação não termina em 8 s, o botão volta a responder (e um clique novo não é desfeito
// pelo fim atrasado do anterior).
const soltarContinuar = () => {
  clearTimeout(relogioDoConstrutor);
  relogioDoConstrutor = null;
  continuando.value = null;
};

const continuar = async agente => {
  if (continuando.value) return;
  tentativaDeContinuar += 1;
  const minha = tentativaDeContinuar;
  continuando.value = agente.id;
  relogioDoConstrutor = setTimeout(
    soltarContinuar,
    ESPERA_MAXIMA_DO_CONSTRUTOR_MS
  );
  try {
    await router.push({
      name: 'autonomia_agents_builder',
      query: { agente: agente.id },
    });
  } finally {
    if (minha === tentativaDeContinuar) soltarContinuar();
  }
};

const enderecoDe = agente =>
  router.resolve(
    agente.agent_type === 'insurance_quote'
      ? rotaDaCotacao(agente)
      : { name: 'autonomia_agent_panel', params: { agentId: agente.id } }
  ).href;

const canaisDe = agente =>
  ocupacao.estado.value === 'pronto'
    ? canaisDoAgente(agente.id, ocupacao.canais.value)
    : null;

// #1433: caixas em que o agente está na equipe (L2), ou null sem a leitura.
const equipeDe = agente =>
  ocupacao.estado.value === 'pronto'
    ? caixasDaEquipe(agente.id, ocupacao.canais.value).map(canal => canal.name)
    : null;

// Externo aparece com a foto da caixa em que atende; sem ela (ou sem a L2), com a foto própria.
const fotoDe = agente => fotoDoAgente(agente, canaisDe(agente), caixas.value);

// A página do agente de outro sistema é a mesma rota dos nossos, com `?origem=webhook`.
const rotaDoOutro = agente => ({
  name: 'autonomia_agent_panel',
  params: { agentId: agente.id },
  query: { origem: 'webhook' },
});
const hrefDoOutro = agente => router.resolve(rotaDoOutro(agente)).href;
const abrirOutro = agente => router.push(rotaDoOutro(agente));
const conectarOutro = () =>
  router.push({
    name: 'autonomia_agents_builder',
    query: { conectar: 'outro' },
  });

const pedirExclusao = agente => {
  pendenteExcluir.value = agente;
  confirmacao.value?.abrir();
};

const aoFecharConfirmacao = () => {
  pendenteExcluir.value = null;
};

const excluir = async () => {
  if (!pendenteExcluir.value || excluindo.value) return;
  excluindo.value = true;
  try {
    await store.dispatch('autonomiaAgents/delete', pendenteExcluir.value.id);
    useAlert(t('AGENTS.JORNADA.EXCLUIR.FEITO'));
  } catch {
    useAlert(
      `${t('AGENTS.JORNADA.ERRO.EXCLUIR')} ${t('AGENTS.JORNADA.ERRO.EXCLUIR_GARANTIA')}`
    );
  } finally {
    excluindo.value = false;
    confirmacao.value?.fechar();
  }
};

onMounted(() => {
  carregar();
  store.dispatch('agentBots/get');
  relogioDasLeituras = setTimeout(() => {
    esperaVencida.value = true;
  }, ESPERA_MAXIMA_DAS_LEITURAS_MS);
});
onBeforeUnmount(() => {
  clearTimeout(relogioDasLeituras);
  clearTimeout(relogioDoConstrutor);
});
</script>

<template>
  <div class="w-full h-full overflow-y-auto bg-n-background">
    <div
      class="relative flex flex-col w-full gap-6 px-4 py-6 pb-28 mx-auto md:px-6 md:pb-6"
      :class="vazia ? 'max-w-5xl' : 'max-w-6xl'"
    >
      <!-- T01 · nenhum agente ainda -->
      <AgentesHeroi
        v-if="vazia"
        :titulo="t('AGENTS.JORNADA.HEROI.TITULO')"
        :texto="
          podeGerenciar
            ? t('AGENTS.JORNADA.MODELOS.ESCOLHA')
            : t('AGENTS.JORNADA.HEROI.SO_VER')
        "
      >
        <ul
          :aria-label="t('AGENTS.JORNADA.MODELOS.ROTULO')"
          class="grid grid-cols-1 gap-4 p-0 m-0 list-none md:grid-cols-3"
        >
          <ModeloCartao
            v-for="modelo in MODELOS"
            :key="modelo.chave"
            :modelo="modelo"
            :pode-usar="podeGerenciar"
            :comecando="comecandoModelo === modelo.chave"
            :bloqueado="!!comecandoModelo && comecandoModelo !== modelo.chave"
            :falhou="modeloQueFalhou === modelo.chave"
            @usar="usarModelo"
          />
        </ul>
        <div
          v-if="semCanal"
          data-sem-canal
          class="flex flex-col gap-2 p-4 text-sm rounded-2xl bg-n-amber-2 text-n-slate-12"
        >
          <p class="m-0">{{ t('AGENTS.JORNADA.HEROI.SEM_CANAL') }}</p>
          <a
            v-if="podeConectarCanal"
            :href="linkConectarCanal"
            target="_blank"
            rel="noopener noreferrer"
            class="relative inline-flex items-center gap-1 font-semibold underline min-h-11 w-fit text-n-slate-12 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-11"
          >
            {{ t('AGENTS.JORNADA.HEROI.CONECTAR_CANAL') }}
            <span class="i-lucide-external-link size-4" aria-hidden="true" />
            <span class="sr-only">{{
              t('AGENTS.JORNADA.COMUM.NOVA_ABA')
            }}</span>
          </a>
          <p v-else class="m-0 text-n-slate-11">
            {{ t('AGENTS.JORNADA.HEROI.SEM_CANAL_SEM_PERMISSAO') }}
          </p>
        </div>
        <div
          v-if="podeGerenciar"
          class="flex flex-col gap-3 pt-5 border-t border-white/15"
        >
          <p class="m-0">
            <button
              data-do-meu-jeito
              type="button"
              class="px-0 text-base font-semibold text-white underline text-start min-h-11 focus-visible:outline focus-visible:outline-2 focus-visible:outline-white"
              @click="usarModelo(MODELO_DO_MEU_JEITO)"
            >
              {{ t('AGENTS.JORNADA.MODELOS.DO_MEU_JEITO') }}
            </button>
          </p>
          <p class="flex flex-col m-0">
            <button
              data-copiloto
              type="button"
              aria-describedby="copiloto-heroi-texto"
              class="px-0 text-base font-semibold text-white underline text-start min-h-11 focus-visible:outline focus-visible:outline-2 focus-visible:outline-white"
              @click="usarCopiloto"
            >
              {{ t('AGENTS.JORNADA.MODELOS.COPILOTO') }}
            </button>
            <span id="copiloto-heroi-texto" class="text-sm text-white/80">
              {{ t('AGENTS.JORNADA.MODELOS.COPILOTO_TEXTO') }}
            </span>
          </p>
        </div>
      </AgentesHeroi>

      <!-- T02 · lista (também carregando e erro) -->
      <template v-else>
        <AgentesHeroi
          compacto
          :titulo="t('AGENTS.JORNADA.LISTA.TITULO')"
          :texto="t('AGENTS.JORNADA.LISTA.TEXTO')"
        >
          <template #detalhe>
            <p
              v-if="!esperando && !falhou"
              data-contagem
              class="m-0 text-sm tabular-nums text-white/80"
            >
              {{ contagemTexto }}
            </p>
            <p v-if="!podeGerenciar" class="m-0 text-sm text-white">
              {{ t('AGENTS.JORNADA.LISTA.SO_VER') }}
            </p>
          </template>
          <template v-if="podeGerenciar" #acoes>
            <AgenteBotao
              data-criar
              variante="branco"
              tamanho="lg"
              icone="i-lucide-plus"
              class="hidden md:inline-flex"
              @click="abrirPaginaCriar"
            >
              {{ t('AGENTS.JORNADA.LISTA.CRIAR') }}
            </AgenteBotao>
          </template>
        </AgentesHeroi>

        <template v-if="esperando">
          <p role="status" class="sr-only">
            {{ t('AGENTS.JORNADA.LISTA.CARREGANDO') }}
          </p>
          <ul
            aria-hidden="true"
            class="grid grid-cols-1 gap-4 p-0 m-0 list-none sm:grid-cols-2 lg:grid-cols-3"
          >
            <!-- Esqueleto de um cartão: avatar e três linhas, como no protótipo. -->
            <li
              v-for="indice in ESQUELETOS"
              :key="indice"
              data-esqueleto
              class="flex flex-col gap-3 p-5 min-h-44 rounded-2xl bg-n-solid-1 ring-1 ring-inset ring-n-weak dark:ring-n-slate-6"
            >
              <span
                class="rounded-full size-12 bg-n-slate-3 motion-safe:animate-pulse"
              />
              <span
                class="w-3/5 h-4 rounded-lg bg-n-slate-3 motion-safe:animate-pulse"
              />
              <span
                class="w-11/12 h-3.5 rounded-lg bg-n-slate-3 motion-safe:animate-pulse"
              />
              <span
                class="w-3/4 h-3.5 rounded-lg bg-n-slate-3 motion-safe:animate-pulse"
              />
            </li>
          </ul>
        </template>

        <AgenteErro
          v-else-if="falhou"
          :titulo="t('AGENTS.JORNADA.ERRO.LISTA')"
          :garantia="t('AGENTS.JORNADA.ERRO.LISTA_GARANTIA')"
          :acao="t('AGENTS.JORNADA.COMUM.TENTAR_DE_NOVO')"
          @acao="tentarDeNovo"
        />

        <template v-else>
          <ul
            :aria-label="t('AGENTS.JORNADA.LISTA.SEUS_AGENTES')"
            class="grid grid-cols-1 gap-4 p-0 m-0 list-none sm:grid-cols-2 lg:grid-cols-3"
          >
            <template
              v-for="{ tipo, agente } in lista"
              :key="`${tipo}-${agente.id}`"
            >
              <AgenteOutroSistemaCartao
                v-if="tipo === 'outro'"
                :agente="agente"
                :canais="canaisDoOutro(agente)"
                :href="hrefDoOutro(agente)"
                @abrir="abrirOutro"
              />
              <AgenteCartao
                v-else
                :agente="agente"
                :href="enderecoDe(agente)"
                :numeros="semana.numerosDe(agente.id)"
                :canais="canaisDe(agente)"
                :equipe="equipeDe(agente)"
                :foto="fotoDe(agente)"
                :pode-gerenciar="podeGerenciar"
                :continuando="continuando === agente.id"
                @abrir="abrirAgente"
                @abrir-cotacao="abrirCotacao"
                @continuar="continuar"
                @excluir="pedirExclusao"
              />
            </template>
          </ul>
          <p v-if="podeGerenciar" class="flex flex-wrap gap-2 m-0">
            <AgenteBotao
              data-ver-modelos
              variante="fantasma"
              @click="abrirPaginaCriar"
            >
              {{ t('AGENTS.JORNADA.LISTA.VER_MODELOS') }}
            </AgenteBotao>
            <AgenteBotao
              data-conectar-outro
              variante="fantasma"
              icone="i-lucide-link"
              @click="conectarOutro"
            >
              {{ t('AGENTS.OUTRO_SISTEMA.CONECTAR') }}
            </AgenteBotao>
          </p>
        </template>

        <div
          v-if="podeGerenciar && !carregando"
          class="fixed inset-x-0 bottom-0 z-20 p-4 border-t md:hidden bg-n-solid-1 border-n-weak"
        >
          <AgenteBotao
            data-criar-celular
            tamanho="xl"
            bloco
            icone="i-lucide-plus"
            @click="abrirPaginaCriar"
          >
            {{ t('AGENTS.JORNADA.LISTA.CRIAR') }}
          </AgenteBotao>
        </div>
      </template>
    </div>

    <AgenteConfirmacao
      ref="confirmacao"
      :titulo="t('AGENTS.JORNADA.EXCLUIR.TITULO')"
      :texto="t('AGENTS.JORNADA.EXCLUIR.TEXTO')"
      :confirmar="t('AGENTS.JORNADA.EXCLUIR.CONFIRMAR')"
      :carregando="excluindo"
      @confirmar="excluir"
      @fechada="aoFecharConfirmacao"
    />
  </div>
</template>
