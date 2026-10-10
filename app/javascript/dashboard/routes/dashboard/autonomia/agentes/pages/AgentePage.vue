<script setup>
import { computed, onBeforeUnmount, onMounted, ref, toRef, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { useCanManage } from 'dashboard/composables/useCanManage';
import FaqSuggestionsAPI from 'dashboard/api/autonomia/faqSuggestions';
import AgenteErro from '../components/AgenteErro.vue';
import PaginaHeroi from '../components/pagina/PaginaHeroi.vue';
import PaginaBlocos from '../components/pagina/PaginaBlocos.vue';
import AgenteSemana from '../components/pagina/AgenteSemana.vue';
import DialogoAcao from '../components/pagina/DialogoAcao.vue';
import GavetaTestar from '../components/pagina/GavetaTestar.vue';
import GavetaOQueSabe from '../components/pagina/GavetaOQueSabe.vue';
import GavetaOndeQuando from '../components/pagina/GavetaOndeQuando.vue';
import GavetaConversas from '../components/pagina/GavetaConversas.vue';
import GavetaFotoNome from '../components/pagina/GavetaFotoNome.vue';
import GavetaVersoes from '../components/pagina/GavetaVersoes.vue';
import GavetaInstrucoes from '../components/pagina/GavetaInstrucoes.vue';
import MudarConversando from '../components/pagina/MudarConversando.vue';
import {
  ESTADO_PAGINA,
  useAgenteDaPagina,
} from '../composables/useAgenteDaPagina';
import { useCanaisDoAgente } from '../composables/useCanaisDoAgente';
import { useNumerosDaSemana } from '../composables/useNumerosDaSemana';
import { ESTADO } from '../utils/estadoDoAgente';
import { horariosDasCaixas } from '../utils/horarios';
import {
  GAVETA,
  chaveDoQuando,
  ehCotacao,
  ehInterno,
  ehManual,
  estadoDeOperacao,
  gavetasPermitidas,
  podeMudarConversando,
  quandoDoAgente,
} from '../utils/pagina';

// #1181 PR3 — página única do agente (protótipo T07), atrás da flag autonomia_agents_journey.
// Herói navy (nome, onde responde, interruptor Atendendo/Parado, ação principal e Mais opções),
// números da semana (L1 filtrada por agente), Testar e os blocos com "Alterar". Cada "Alterar" abre
// uma gaveta (T08–T14); Mudar conversando (T11) troca o conteúdo da página. Parar (T15) e Excluir
// (T16) pedem confirmação; voltar a atender passa pela confirmação de canal. Quem só vê lê e testa.
// `gaveta` vem do seletor da rota (o :tab antigo traduzido) e abre a gaveta certa ao carregar.
const props = defineProps({
  agentId: { type: [String, Number], required: true },
  gaveta: { type: String, default: null },
});

const { t } = useI18n();
const store = useStore();
const route = useRoute();
const router = useRouter();
const podeGerenciar = useCanManage('autonomia_manage');
const NS = 'AGENTS.JORNADA.PAGINA';

const idRef = toRef(props, 'agentId');
const { agente, estado, carregar } = useAgenteDaPagina(idRef);
const canais = useCanaisDoAgente(idRef);
const semana = useNumerosDaSemana({ agentId: Number(props.agentId) });
const caixas = useMapGetter('inboxes/getInboxes');
const fontes = useMapGetter('autonomiaSources/getKnowledgeSources');
const flagsFontes = useMapGetter('autonomiaSources/getUIFlags');

const aberta = ref(null);
const vista = ref('pagina');
const perguntaDoTeste = ref('');
const origemMudar = ref('geral');
const testeInicial = ref(null);
const nomeSugerido = ref('');
const abaConversas = ref('respondidas');
const perguntas = ref([]);
const fontesFalharam = ref(false);
const alternando = ref(false);
const excluindo = ref(false);
const dialogoParar = ref(null);
const dialogoExcluir = ref(null);
const dialogoEscrever = ref(null);
let gavetaDaUrlAberta = null;

const pronto = computed(
  () => estado.value === ESTADO_PAGINA.PRONTO && Boolean(agente.value?.id)
);
const nome = computed(
  () => agente.value?.name || t('AGENTS.JORNADA.COMUM.NOVO_AGENTE')
);
const estadoDaPagina = computed(() => estadoDeOperacao(agente.value));
const atendendo = computed(() => estadoDaPagina.value === ESTADO.ATENDENDO);
const cotacao = computed(() => ehCotacao(agente.value));
const manual = computed(() => ehManual(agente.value));
const interno = computed(() => ehInterno(agente.value));
const podeMudar = computed(
  () => podeGerenciar.value && podeMudarConversando(agente.value)
);
const permitidas = computed(() =>
  gavetasPermitidas(agente.value, podeGerenciar.value)
);

// Onde responde: nome da caixa pela L2 (ou pelos canais do agente); sem a leitura, só a contagem.
const quando = computed(() =>
  t(`${NS}.QUANDO.${chaveDoQuando(quandoDoAgente(agente.value))}`)
);
const atuais = computed(() => canais.atuais.value);
const quantosCanais = computed(() =>
  canais.estado.value === 'pronto'
    ? atuais.value.length
    : agente.value?.channels_count || 0
);
const temCanal = computed(() => quantosCanais.value > 0);
const umCanal = computed(() =>
  canais.estado.value === 'pronto' && atuais.value.length === 1
    ? atuais.value[0].name
    : null
);

const ondeNoHeroi = computed(() => {
  if (interno.value) return '';
  if (!temCanal.value) return t(`${NS}.NENHUM_CANAL`);
  const ligado = atendendo.value;
  if (umCanal.value) {
    return t(ligado ? `${NS}.RESPONDE_NO` : `${NS}.PARADO_NO`, {
      canal: umCanal.value,
      quando: quando.value,
    });
  }
  const n = quantosCanais.value;
  return t(
    ligado ? `${NS}.RESPONDE_EM_N` : `${NS}.PARADO_EM_N`,
    { n, quando: quando.value },
    n
  );
});

const textoOnde = computed(() => {
  if (umCanal.value) {
    return t(`${NS}.BLOCO_ONDE.TEXTO`, {
      canal: umCanal.value,
      quando: quando.value,
    });
  }
  const n = quantosCanais.value;
  return t(`${NS}.BLOCO_ONDE.TEXTO_N`, { n, quando: quando.value }, n);
});

const horarios = computed(() => horariosDasCaixas(caixas.value, t));

const acaoPrincipal = computed(() => {
  if (cotacao.value) return null;
  return manual.value ? 'instrucoes' : 'mudar';
});

const itensMais = computed(() => {
  const versoes = {
    chave: GAVETA.VERSOES,
    texto: t(`${NS}.VERSOES.TITULO`),
    icone: 'i-lucide-history',
  };
  if (!podeGerenciar.value) return cotacao.value ? [] : [versoes];
  const foto = {
    chave: GAVETA.FOTO,
    texto: t(`${NS}.FOTO.TITULO`),
    icone: 'i-lucide-image',
  };
  if (cotacao.value) return [foto];
  return [
    foto,
    versoes,
    {
      chave: GAVETA.INSTRUCOES,
      texto: manual.value
        ? t(`${NS}.EDITAR_INSTRUCOES`)
        : t(`${NS}.INSTRUCOES.MENU`),
      icone: 'i-lucide-pencil',
    },
    {
      chave: 'excluir',
      texto: t(`${NS}.EXCLUIR.MENU`),
      icone: 'i-lucide-trash-2',
      perigo: true,
      separar: true,
    },
  ];
});

const hrefLista = computed(
  () => router.resolve({ name: 'autonomia_agents_index' }).href
);
const irParaLista = () => router.push({ name: 'autonomia_agents_index' });

// ---------- gavetas ----------
const abrir = (gaveta, extra = {}) => {
  if (!permitidas.value.includes(gaveta)) return;
  perguntaDoTeste.value = extra.pergunta || '';
  if (extra.aba) abaConversas.value = extra.aba;
  aberta.value = gaveta;
};

// Gaveta aberta pelo :tab antigo: ao sair dela, a URL volta a ser a da página (F5 não reabre).
const limparAbaDaUrl = () => {
  if (!route.params.tab) return;
  router.replace({
    name: 'autonomia_agent_panel',
    params: { agentId: props.agentId },
  });
};

const fechar = () => {
  aberta.value = null;
  nomeSugerido.value = '';
  limparAbaDaUrl();
};

const abrirDaUrl = () => {
  if (!pronto.value || !props.gaveta || props.gaveta === gavetaDaUrlAberta) {
    return;
  }
  gavetaDaUrlAberta = props.gaveta;
  abrir(props.gaveta);
};

watch(() => [props.gaveta, pronto.value], abrirDaUrl, { immediate: true });
watch(
  () => props.gaveta,
  gaveta => {
    if (!gaveta) gavetaDaUrlAberta = null;
  }
);

// ---------- leituras ----------
// Se a leitura falha, a contagem cai em "Só o que você contou" e a gaveta O que sabe mostra o erro
// com "Tentar de novo".
// A store zera a lista antes de cada leitura, e se relê a cada 4 s enquanto algo está sendo lido.
// Para a lista e a contagem não piscarem, a página guarda a última lista lida e só a troca quando
// a store não está lendo. `null` = ainda não leu nesta página (a gaveta mostra o carregando).
const fontesLidas = ref(null);
const lendoFontes = computed(() => Boolean(flagsFontes.value?.fetchingList));
watch([fontes, lendoFontes], ([lista, lendo]) => {
  if (lendo || fontesLidas.value === null) return;
  fontesLidas.value = lista || [];
});
const listaDeFontes = computed(() => fontesLidas.value || []);

const lerFontes = async () => {
  fontesFalharam.value = false;
  try {
    await store.dispatch('autonomiaSources/fetch', {
      agentId: Number(props.agentId),
    });
    fontesLidas.value = fontes.value || [];
  } catch {
    fontesFalharam.value = true;
  }
};

// Perguntas de clientes para conferir: só para quem gerencia e nos agentes que aprendem pela base.
const lerPerguntas = async () => {
  if (!podeGerenciar.value || cotacao.value) return;
  try {
    const { data } = await FaqSuggestionsAPI.list(Number(props.agentId), {
      status: 'pending',
    });
    perguntas.value = data?.payload || [];
  } catch {
    // Sem a leitura, a seção de perguntas some (é um convite, não um dado de que a tela dependa).
    perguntas.value = [];
  }
};

const carregarTudo = async () => {
  canais.carregar();
  await carregar();
  if (estado.value !== ESTADO_PAGINA.PRONTO) return;
  lerFontes();
  lerPerguntas();
};

const tentarDeNovo = () => {
  semana.carregar();
  carregarTudo();
};

onMounted(carregarTudo);
onBeforeUnmount(() => {
  store.dispatch('autonomiaSources/stopPolling');
});

// ---------- ações ----------
const perguntar = texto => abrir(GAVETA.TESTAR, { pergunta: texto });

const mudar = (origem, inicial = null) => {
  if (!podeMudar.value) return;
  aberta.value = null;
  limparAbaDaUrl();
  origemMudar.value = origem;
  testeInicial.value = inicial;
  vista.value = 'mudar';
};

const sairDoMudar = () => {
  vista.value = 'pagina';
  testeInicial.value = null;
};

const voltarNome = antigo => {
  vista.value = 'pagina';
  nomeSugerido.value = antigo;
  aberta.value = GAVETA.FOTO;
};

const escrever = () => {
  if (manual.value) abrir(GAVETA.INSTRUCOES);
  else dialogoEscrever.value?.abrir();
};

const escolherCanal = () =>
  abrir(atendendo.value ? GAVETA.ONDE : GAVETA.VOLTAR);

const voltarInterno = async () => {
  alternando.value = true;
  try {
    await store.dispatch('autonomiaAgents/update', {
      id: agente.value.id,
      enabled: true,
      status: 'active',
    });
    useAlert(t(`${NS}.VOLTAR_INTERNO.FEITO`, { nome: nome.value }));
  } catch {
    useAlert(t(`${NS}.VOLTAR_INTERNO.ERRO`));
  } finally {
    alternando.value = false;
  }
};

const alternar = ligar => {
  if (!ligar) {
    dialogoParar.value?.abrir();
    return;
  }
  if (interno.value) {
    voltarInterno();
    return;
  }
  abrir(GAVETA.VOLTAR);
};

const escolherMais = chave => {
  if (chave === 'excluir') dialogoExcluir.value?.abrir();
  else if (chave === GAVETA.INSTRUCOES) escrever();
  else abrir(chave);
};

const acaoDoHeroi = () => {
  if (acaoPrincipal.value === 'instrucoes') escrever();
  else mudar('geral');
};

const parar = async () => {
  await store.dispatch('autonomiaAgents/update', {
    id: agente.value.id,
    status: 'paused',
  });
  useAlert(t(`${NS}.PARAR.FEITO`, { nome: nome.value }));
};

// A store tira o agente da lista antes de a promessa voltar: sem `excluindo`, a página cairia no
// "Não deu para abrir" até a lista carregar. Enquanto sai, fica o esqueleto.
const excluir = async () => {
  const quem = nome.value;
  excluindo.value = true;
  try {
    await store.dispatch('autonomiaAgents/delete', agente.value.id);
  } catch (erro) {
    excluindo.value = false;
    throw erro;
  }
  useAlert(t(`${NS}.EXCLUIR.FEITO`, { nome: quem }));
  irParaLista();
};

// T16 → T15: "Se quiser só parar por um tempo, use Parar de atender."
const pararEmVezDeExcluir = () => {
  dialogoExcluir.value?.fechar();
  dialogoParar.value?.abrir();
};

const tirarPergunta = id => {
  perguntas.value = perguntas.value.filter(item => item.id !== id);
  lerFontes();
};
</script>

<template>
  <div class="w-full h-full overflow-y-auto bg-n-background">
    <div
      class="flex flex-col w-full gap-6 px-4 py-6 mx-auto md:px-6"
      :class="vista === 'mudar' ? 'max-w-6xl' : 'max-w-[55rem]'"
    >
      <!-- t07-carregando -->
      <template v-if="estado === ESTADO_PAGINA.CARREGANDO || excluindo">
        <h1 class="sr-only">{{ t(`${NS}.TITULO_SR`) }}</h1>
        <p role="status" class="sr-only">{{ t(`${NS}.CARREGANDO`) }}</p>
        <div
          data-esqueleto
          aria-hidden="true"
          class="flex items-center gap-4 px-6 py-8 rounded-3xl bg-[#0D2344] dark:bg-[#12305E]"
        >
          <span
            class="rounded-full size-16 bg-white/15 motion-safe:animate-pulse"
          />
          <span class="flex flex-col gap-2 grow">
            <span
              class="w-2/5 h-7 rounded-lg bg-white/15 motion-safe:animate-pulse"
            />
            <span
              class="w-3/5 h-4 rounded-lg bg-white/15 motion-safe:animate-pulse"
            />
          </span>
        </div>
        <div aria-hidden="true" class="flex flex-col gap-4">
          <span
            v-for="indice in 5"
            :key="indice"
            class="flex flex-col gap-2 p-5 rounded-2xl bg-n-solid-1 ring-1 ring-inset ring-n-weak"
          >
            <span
              class="w-1/3 h-4 rounded-lg bg-n-slate-3 motion-safe:animate-pulse"
            />
            <span
              class="w-3/4 h-3.5 rounded-lg bg-n-slate-3 motion-safe:animate-pulse"
            />
          </span>
        </div>
      </template>

      <!-- t07-naoexiste -->
      <template v-else-if="estado === ESTADO_PAGINA.NAO_EXISTE">
        <h1 class="m-0 text-3xl font-bold text-n-slate-12">
          {{ t('AGENTS.JORNADA.LISTA.TITULO') }}
        </h1>
        <AgenteErro
          data-nao-existe
          tom="ambar"
          :titulo="t(`${NS}.NAO_EXISTE`)"
          :acao="t(`${NS}.VOLTAR_LISTA`)"
          icone-acao="i-lucide-arrow-left"
          @acao="irParaLista"
        />
      </template>

      <!-- t07-erro -->
      <template v-else-if="estado === ESTADO_PAGINA.ERRO || !agente?.id">
        <a
          :href="hrefLista"
          class="inline-flex items-center gap-2 text-sm font-semibold min-h-11 w-fit text-n-blue-11"
          @click.prevent="irParaLista"
        >
          <span
            class="i-lucide-arrow-left size-4 rtl:rotate-180"
            aria-hidden="true"
          />
          {{ t(`${NS}.VOLTAR_LISTA`) }}
        </a>
        <h1 class="m-0 text-3xl font-bold text-n-slate-12">
          {{ agente?.name || t(`${NS}.TITULO_SR`) }}
        </h1>
        <AgenteErro
          data-erro-abrir
          :titulo="
            agente?.name
              ? t(`${NS}.ERRO_ABRIR`, { nome: agente.name })
              : t(`${NS}.ERRO_ABRIR_SEM_NOME`)
          "
          :garantia="t(`${NS}.ERRO_ABRIR_GARANTIA`)"
          :acao="t('AGENTS.JORNADA.COMUM.TENTAR_DE_NOVO')"
          @acao="tentarDeNovo"
        />
      </template>

      <!-- T11 · Mudar conversando -->
      <MudarConversando
        v-else-if="vista === 'mudar'"
        :agente="agente"
        :origem="origemMudar"
        :teste-inicial="testeInicial"
        @sair="sairDoMudar"
        @voltar-nome="voltarNome"
      />

      <!-- T07 -->
      <template v-else>
        <PaginaHeroi
          :nome="nome"
          :foto="agente.avatar_url || ''"
          :estado="estadoDaPagina"
          :onde="ondeNoHeroi"
          :href-lista="hrefLista"
          :pode-gerenciar="podeGerenciar"
          :acao-principal="acaoPrincipal"
          :itens-mais="itensMais"
          :alternando="alternando"
          @voltar-lista="irParaLista"
          @alternar="alternar"
          @acao-principal="acaoDoHeroi"
          @mais="escolherMais"
        />
        <p
          v-if="!atendendo"
          data-faixa-parado
          class="flex items-start gap-3 p-4 m-0 text-sm rounded-2xl bg-n-amber-2 ring-1 ring-inset ring-n-amber-6 text-n-slate-12"
        >
          <span
            class="i-lucide-triangle-alert size-5 shrink-0 text-n-amber-11"
            aria-hidden="true"
          />
          {{ t(`${NS}.PARADO_FAIXA`, { nome }) }}
        </p>
        <p
          v-if="!podeGerenciar"
          data-faixa-so-ver
          class="flex items-start gap-3 p-4 m-0 text-sm rounded-2xl bg-n-blue-2 ring-1 ring-inset ring-n-blue-6 text-n-slate-12"
        >
          <span
            class="i-lucide-lock size-5 shrink-0 text-n-blue-11"
            aria-hidden="true"
          />
          {{ t(`${NS}.SO_VER`) }}
        </p>
        <AgenteSemana
          :numeros="semana.numerosDe(agente.id)"
          :nome="nome"
          :pode-abrir="podeGerenciar && !cotacao"
          @abrir="abrir(GAVETA.CONVERSAS, { aba: $event })"
        />
        <PaginaBlocos
          :agente="agente"
          :nome="nome"
          :pode-gerenciar="podeGerenciar"
          :manual="manual"
          :cotacao="cotacao"
          :interno="interno"
          :tem-canal="temCanal"
          :texto-onde="textoOnde"
          :quantas-fontes="listaDeFontes.length"
          :quantas-perguntas="perguntas.length"
          @perguntar="perguntar"
          @abrir="abrir"
          @mudar="mudar"
          @escrever="escrever"
          @escolher-canal="escolherCanal"
        />
      </template>
    </div>

    <template v-if="pronto && vista === 'pagina'">
      <GavetaTestar
        v-if="aberta === GAVETA.TESTAR"
        :agente="agente"
        :nome="nome"
        :atendendo="atendendo"
        :pode-mudar="podeMudar"
        :pergunta="perguntaDoTeste"
        @fechar="fechar"
        @errado="mudar('teste', $event)"
      />
      <GavetaOQueSabe
        v-else-if="aberta === GAVETA.SABE"
        :agente="agente"
        :nome="nome"
        :pode-gerenciar="podeGerenciar"
        :perguntas="perguntas"
        :fontes="listaDeFontes"
        :carregando-fontes="fontesLidas === null"
        :erro-ler="fontesFalharam"
        @fechar="fechar"
        @reler="lerFontes"
        @pergunta-resolvida="tirarPergunta"
      />
      <GavetaOndeQuando
        v-else-if="aberta === GAVETA.ONDE || aberta === GAVETA.VOLTAR"
        :key="aberta"
        :agente="agente"
        :nome="nome"
        :modo="aberta === GAVETA.VOLTAR ? 'voltar' : 'alterar'"
        :atendendo="atendendo"
        :canais="canais.canais.value"
        :estado-canais="canais.estado.value"
        :atuais="atuais"
        :sem-leitura="canais.semLeitura.value"
        :horarios="horarios"
        @fechar="fechar"
        @pronto="canais.carregar()"
        @reler="canais.carregar()"
        @voltar-a-atender="aberta = GAVETA.VOLTAR"
      />
      <GavetaConversas
        v-else-if="aberta === GAVETA.CONVERSAS"
        :agent-id="agente.id"
        :aba="abaConversas"
        @fechar="fechar"
      />
      <GavetaFotoNome
        v-else-if="aberta === GAVETA.FOTO"
        :agente="agente"
        :nome-sugerido="nomeSugerido"
        @fechar="fechar"
      />
      <GavetaVersoes
        v-else-if="aberta === GAVETA.VERSOES"
        :agente="agente"
        :nome="nome"
        :pode-gerenciar="podeGerenciar"
        @fechar="fechar"
      />
      <GavetaInstrucoes
        v-else-if="aberta === GAVETA.INSTRUCOES"
        :agente="agente"
        :nome="nome"
        @fechar="fechar"
      />
    </template>

    <template v-if="(pronto || excluindo) && podeGerenciar">
      <DialogoAcao
        ref="dialogoParar"
        :titulo="t(`${NS}.PARAR.TITULO`, { nome })"
        :texto="t(`${NS}.PARAR.TEXTO`)"
        :confirmar="t(`${NS}.PARAR.CONFIRMAR`)"
        :rotulo-carregando="t(`${NS}.PARAR.PARANDO`)"
        :erro-titulo="t(`${NS}.PARAR.ERRO`)"
        :erro-garantia="t(`${NS}.PARAR.ERRO_GARANTIA`, { nome })"
        :executar="parar"
      />
      <DialogoAcao
        ref="dialogoExcluir"
        :titulo="t(`${NS}.EXCLUIR.TITULO`, { nome })"
        :texto="t(`${NS}.EXCLUIR.TEXTO`, { nome })"
        :confirmar="t(`${NS}.EXCLUIR.CONFIRMAR`)"
        :rotulo-carregando="t(`${NS}.EXCLUIR.EXCLUINDO`)"
        variante="perigo"
        :erro-titulo="t(`${NS}.EXCLUIR.ERRO`)"
        :erro-garantia="t(`${NS}.EXCLUIR.ERRO_GARANTIA`)"
        :executar="excluir"
      >
        <p v-if="atendendo" data-extra class="m-0 text-sm text-n-slate-11">
          {{ t(`${NS}.EXCLUIR.EXTRA`) }}
          <button
            data-atalho-parar
            type="button"
            class="inline-flex items-center font-semibold underline min-h-11 text-n-blue-11 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-11"
            @click="pararEmVezDeExcluir"
          >
            {{ t(`${NS}.EXCLUIR.EXTRA_ACAO`) }}
          </button>
        </p>
      </DialogoAcao>
      <DialogoAcao
        ref="dialogoEscrever"
        :titulo="t(`${NS}.INSTRUCOES.AVISO_TITULO`)"
        :texto="t(`${NS}.INSTRUCOES.AVISO_TEXTO`, { nome })"
        :confirmar="t(`${NS}.INSTRUCOES.AVISO_CONFIRMAR`)"
        variante="aviso"
        @confirmado="abrir(GAVETA.INSTRUCOES)"
      />
    </template>
  </div>
</template>
