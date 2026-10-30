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
import AgenteSilencios from '../components/pagina/AgenteSilencios.vue';
import DialogoAcao from '../components/pagina/DialogoAcao.vue';
import GavetaTestar from '../components/pagina/GavetaTestar.vue';
import GavetaOQueSabe from '../components/pagina/GavetaOQueSabe.vue';
import GavetaOndeQuando from '../components/pagina/GavetaOndeQuando.vue';
import GavetaOndeQuandoFase2 from '../components/pagina/GavetaOndeQuandoFase2.vue';
import GavetaConversas from '../components/pagina/GavetaConversas.vue';
import GavetaFotoNome from '../components/pagina/GavetaFotoNome.vue';
import GavetaVersoes from '../components/pagina/GavetaVersoes.vue';
import GavetaInstrucoes from '../components/pagina/GavetaInstrucoes.vue';
import GavetaAgenda from '../components/pagina/GavetaAgenda.vue';
import GavetaFerramentas from '../components/pagina/GavetaFerramentas.vue';
import MudarConversando from '../components/pagina/MudarConversando.vue';
import AgenteGaveta from '../components/AgenteGaveta.vue';
import EquipeCanais from '../components/onde/EquipeCanais.vue';
import AjudantePassos from '../components/onde/AjudantePassos.vue';
import BaseDoAgenteLinha from '../components/pagina/BaseDoAgenteLinha.vue';
import GavetaNovaBase from '../components/pagina/GavetaNovaBase.vue';
import { useBaseDoAgente } from '../composables/useBaseDoAgente';
import {
  ESTADO_PAGINA,
  useAgenteDaPagina,
} from '../composables/useAgenteDaPagina';
import { useCanaisDoAgente } from '../composables/useCanaisDoAgente';
import { useNumerosDaSemana } from '../composables/useNumerosDaSemana';
import { useAgendaNovaNaConta } from '../composables/useAgendaNovaNaConta';
import { useSalvarEquipe } from '../composables/useSalvarEquipe';
import { useAjudaDoAgente } from '../composables/useAjudaDoAgente';
import { useFase2 } from '../composables/useFase2';
import { usePainelDesempenho } from '../composables/usePainelDesempenho';
import { precisaDeVoce } from '../utils/estadoDoMaterial';
import { useConferenciasDoMaterial } from '../composables/useConferenciasDoMaterial';
import {
  ehAjudante,
  falaComCliente,
  nomesQueAjuda,
  quemAjuda,
} from '../utils/ajudante';
import { ESTADO, TRABALHANDO } from '../utils/estadoDoAgente';
import { caixasDaEquipe, recebeEmOutrasCaixas } from '../utils/ondeTrabalha';
import { horariosDasCaixas } from '../utils/horarios';
import { resumoOnde } from '../utils/resumoOnde';
import {
  GAVETA,
  chaveDoQuando,
  ehCotacao,
  ehInterno,
  ehManual,
  ehSuperAdmin,
  estadoDeOperacao,
  gavetasPermitidas,
  podeMudarConversando,
  quandoDoAgente,
} from '../utils/pagina';
import { caixaDaFoto, usaFotoDoCanal } from '../utils/fotoDoCanal';

// #1181 PR3 — página única do agente (protótipo T07), atrás da flag autonomia_agents_journey.
// Herói navy (nome, onde responde, interruptor Atendendo/Parado, ação principal e Mais opções),
// números da semana (L1 filtrada por agente), Testar e os blocos com "Alterar". Cada "Alterar" abre
// uma gaveta (T08–T14); Mudar conversando (T11) troca o conteúdo da página. Parar (T15) e Excluir
// (T16) pedem confirmação; voltar a atender passa pela confirmação de canal. Quem só vê lê e testa.
// `gaveta` vem do seletor da rota (o :tab antigo traduzido) e abre a gaveta certa ao carregar.
// #1433 (tema 13): o agente da equipe (`na_equipe`) aparece "Na equipe", com "Onde {nome} trabalha" (caixa e
// papel) no lugar de "Onde e quando responde"; "Mudar" abre direto os passos do agente da equipe (EquipeCanais).
// Ligar de novo um agente da equipe parado não pede canal: as caixas dele continuam.
// #1720 (decisão do Rodrigo de 16/10) — SÓ COM A FASE 2: todo agente usa a gaveta nova (GavetaOndeQuandoFase2), inclusive o
// da equipe (sem "Onde {nome} trabalha"), e o herói e o resumo dizem a mesma frase (utils/resumoOnde). Sem a Fase 2, a
// página é a de antes, igual à main (textos, gaveta, "Onde {nome} trabalha").
// Tema 14 (#1434): o ajudante aparece "Ajudando", sem "Testar" (como cliente) e sem "Quando passa para a
// equipe"; "Quem {nome} ajuda" e "Quando chamar" ("GET /ajuda") com "Mudar" abrindo os passos do ajudante.
const props = defineProps({
  agentId: { type: [String, Number], required: true },
  gaveta: { type: String, default: null },
});

const { t } = useI18n();
const store = useStore();
const route = useRoute();
const router = useRouter();
const podeGerenciar = useCanManage('autonomia_manage');

const idRef = toRef(props, 'agentId');
const { agente, estado, carregar } = useAgenteDaPagina(idRef);
const canais = useCanaisDoAgente(idRef);
const semana = useNumerosDaSemana({ agentId: Number(props.agentId) });
const caixas = useMapGetter('inboxes/getInboxes');
const fontes = useMapGetter('autonomiaSources/getKnowledgeSources');
const flagsFontes = useMapGetter('autonomiaSources/getUIFlags');
const agendaNova = useAgendaNovaNaConta();
const usuario = useMapGetter('getCurrentUser');

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
const trabalhando = computed(() => TRABALHANDO.includes(estadoDaPagina.value));
const naEquipe = computed(() => agente.value?.na_equipe === true);
const fase2 = useFase2();
// Caixas em que ele está na equipe (L2), ou [] sem a leitura; null quando não é agente da equipe.
const equipe = computed(() => {
  if (fase2.value || !naEquipe.value) return null;
  return canais.estado.value === 'pronto' && !canais.semLeitura.value
    ? caixasDaEquipe(Number(props.agentId), canais.canais.value)
    : [];
});
// #1433 ("a, para todos os agentes"): quem atende primeiro também recebe em outras caixas quando alguém
// passa. A gaveta "Onde e quando" mostra a escolha; o resumo, as caixas. Só com a Fase 2 e a leitura L2.
// #1720: com a Fase 2, o agente da equipe também (a mesma gaveta para todos).
const recebeEmOutras = computed(
  () => fase2.value && recebeEmOutrasCaixas(agente.value)
);
const tambemRecebeEm = computed(() =>
  recebeEmOutras.value &&
  canais.estado.value === 'pronto' &&
  !canais.semLeitura.value
    ? caixasDaEquipe(Number(props.agentId), canais.canais.value)
    : []
);
const salvarEquipe = useSalvarEquipe();
const EQUIPE = 'equipe';
const AJUDA = 'ajuda';
const ajudante = computed(() => ehAjudante(agente.value));
const ajudaDoAgente = useAjudaDoAgente();
// Tema 14: ligar e parar o ajudante falam de ajudar outros agentes, nunca de atender nem de passar conversas
// para a equipe. Os demais agentes seguem com os textos de sempre.
const doInterruptor = (deSempre, doAjudante) =>
  ajudante.value ? doAjudante : deSempre;
const registros = useMapGetter('autonomiaAgents/getRecords');
const leituraDosAgentes = ref('pronto');
const passoDaAjuda = ref('quem');
// Quem ele ajuda (do agente) e o "quando chamar" (da rota /ajuda), ou null quando não é ajudante.
const ajuda = computed(() =>
  ajudante.value
    ? {
        principais: quemAjuda(agente.value),
        quando: ajudaDoAgente.quando.value,
      }
    : null
);
const cotacao = computed(() => ehCotacao(agente.value));
// #1429 F3 — a base de seguros: a linha no resumo e a gaveta do antes e depois. Só com a Fase 2 (sem ela o servidor
// responde 404); a Lia (cotação) não recebe nada disso.
const BASE = 'base';
const baseDoAgente = useBaseDoAgente(idRef);
const temBase = computed(() => fase2.value && !cotacao.value);
const mostraBase = computed(
  () => temBase.value && baseDoAgente.temOQueMostrar.value
);
const manual = computed(() => ehManual(agente.value));
const interno = computed(() => ehInterno(agente.value));
// #1709: "Quando {nome} não respondeu" só no agente que fala com o cliente (sem ajudante, interno nem cotação).
const mostraSilencios = computed(
  () => Boolean(agente.value) && falaComCliente(agente.value) && !cotacao.value
);
const podeMudar = computed(
  () => podeGerenciar.value && podeMudarConversando(agente.value)
);
const superAdmin = computed(() => ehSuperAdmin(usuario.value));
const permitidas = computed(() =>
  gavetasPermitidas(agente.value, podeGerenciar.value, {
    agendaNova: agendaNova.value,
    superAdmin: superAdmin.value,
  })
);

// Onde responde: nome da caixa pela L2 (ou pelos canais do agente); sem a leitura, só a contagem.
const TEXTO_DO_QUANDO = {
  ALWAYS: () => t('AGENTS.JORNADA.PAGINA.QUANDO.ALWAYS'),
  BUSINESS_HOURS: () => t('AGENTS.JORNADA.PAGINA.QUANDO.BUSINESS_HOURS'),
  OUTSIDE_BUSINESS_HOURS: () =>
    t('AGENTS.JORNADA.PAGINA.QUANDO.OUTSIDE_BUSINESS_HOURS'),
};
const quando = computed(() =>
  TEXTO_DO_QUANDO[chaveDoQuando(quandoDoAgente(agente.value))]()
);
const atuais = computed(() => canais.atuais.value);
// Antes da leitura das caixas, a contagem do servidor (porta e área juntas). #1720, com a Fase 2: o agente só da
// equipe não atende primeiro em nenhuma.
const quantosAntesDaLeitura = computed(() =>
  fase2.value && naEquipe.value ? 0 : agente.value?.channels_count || 0
);
const quantosCanais = computed(() =>
  canais.estado.value === 'pronto'
    ? atuais.value.length
    : quantosAntesDaLeitura.value
);
const temCanal = computed(() => quantosCanais.value > 0);
const umCanal = computed(() =>
  canais.estado.value === 'pronto' && atuais.value.length === 1
    ? atuais.value[0].name
    : null
);

// Externo: o cliente vê a foto da caixa (a primeira de "Responde no …"); sem ela, a foto própria.
const canalDaFoto = computed(() =>
  canais.estado.value === 'pronto'
    ? caixaDaFoto(agente.value, atuais.value, caixas.value)
    : null
);
const foto = computed(
  () => canalDaFoto.value?.foto || agente.value?.avatar_url || ''
);

// #1720, só com a Fase 2: uma linha com onde atende primeiro e onde recebe quando alguém passar; parado, só os
// canais. O agente da equipe sem a leitura das caixas diz só que recebe quando alguém passa.
const resumoDaFase2 = computed(() => {
  if (naEquipe.value && !tambemRecebeEm.value.length) {
    return t('AGENTS.JORNADA.ONDE.RECEBE');
  }
  return resumoOnde(t, {
    primeiro: umCanal.value,
    quantosPrimeiro: quantosCanais.value,
    recebe: tambemRecebeEm.value,
    quando: quando.value,
    parado: !trabalhando.value,
  });
});

const ondeNoHeroi = computed(() => {
  if (ajudante.value) {
    const nomes = nomesQueAjuda(agente.value);
    return nomes ? t('AGENTS.JORNADA.ONDE.AJUDA', { agentes: nomes }) : '';
  }
  if (interno.value) return '';
  if (fase2.value) return resumoDaFase2.value;
  if (equipe.value) {
    return equipe.value.length
      ? t('AGENTS.JORNADA.CARTAO.RECEBE_EM', {
          caixas: equipe.value.map(canal => canal.name).join(', '),
        })
      : t('AGENTS.JORNADA.ONDE.RECEBE');
  }
  if (!temCanal.value) return t('AGENTS.JORNADA.PAGINA.NENHUM_CANAL');
  const ligado = atendendo.value;
  if (umCanal.value) {
    const valores = { canal: umCanal.value, quando: quando.value };
    return ligado
      ? t('AGENTS.JORNADA.PAGINA.RESPONDE_NO', valores)
      : t('AGENTS.JORNADA.PAGINA.PARADO_NO', valores);
  }
  const n = quantosCanais.value;
  const valores = { n, quando: quando.value };
  return ligado
    ? t('AGENTS.JORNADA.PAGINA.RESPONDE_EM_N', valores, n)
    : t('AGENTS.JORNADA.PAGINA.PARADO_EM_N', valores, n);
});

const textoOnde = computed(() => {
  if (fase2.value) return resumoDaFase2.value;
  if (umCanal.value) {
    return t('AGENTS.JORNADA.PAGINA.BLOCO_ONDE.TEXTO', {
      canal: umCanal.value,
      quando: quando.value,
    });
  }
  const n = quantosCanais.value;
  return t(
    'AGENTS.JORNADA.PAGINA.BLOCO_ONDE.TEXTO_N',
    { n, quando: quando.value },
    n
  );
});

const horarios = computed(() => horariosDasCaixas(caixas.value, t));

const acaoPrincipal = computed(() => {
  if (cotacao.value) return null;
  return manual.value ? 'instrucoes' : 'mudar';
});

const itensMais = computed(() => {
  const versoes = {
    chave: GAVETA.VERSOES,
    texto: t('AGENTS.JORNADA.PAGINA.VERSOES.TITULO'),
    icone: 'i-lucide-history',
  };
  if (!podeGerenciar.value) return cotacao.value ? [] : [versoes];
  const soNome = usaFotoDoCanal(agente.value);
  const fotoENome = {
    chave: GAVETA.FOTO,
    texto: soNome
      ? t('AGENTS.JORNADA.PAGINA.FOTO.TITULO_NOME')
      : t('AGENTS.JORNADA.PAGINA.FOTO.TITULO'),
    icone: soNome ? 'i-lucide-user-pen' : 'i-lucide-image',
  };
  // Ferramentas: só o SuperAdmin que gerencia (gavetasPermitidas), como a aba do painel antigo.
  const ferramentas = permitidas.value.includes(GAVETA.FERRAMENTAS)
    ? [
        {
          chave: GAVETA.FERRAMENTAS,
          texto: t('AGENTS.JORNADA.PAGINA.FERRAMENTAS.MENU'),
          icone: 'i-lucide-wrench',
        },
      ]
    : [];
  if (cotacao.value) return [fotoENome, ...ferramentas];
  return [
    fotoENome,
    versoes,
    {
      chave: GAVETA.INSTRUCOES,
      texto: manual.value
        ? t('AGENTS.JORNADA.PAGINA.EDITAR_INSTRUCOES')
        : t('AGENTS.JORNADA.PAGINA.INSTRUCOES.MENU'),
      icone: 'i-lucide-pencil',
    },
    ...ferramentas,
    {
      chave: 'excluir',
      texto: t('AGENTS.JORNADA.PAGINA.EXCLUIR.MENU'),
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
// #2226 — "Ver tudo de {nome}": o painel de desempenho, só com a flag ligada na conta. O agente de cotação não tem
// painel (#2251: a leitura é de atendimento, não de cotação), então o link não aparece nele.
const painelDesempenho = usePainelDesempenho();
const rotaDoDesempenho = computed(() => ({
  name: 'autonomia_agent_desempenho',
  params: { agentId: props.agentId },
}));
const hrefDesempenho = computed(() =>
  painelDesempenho.value && !cotacao.value
    ? router.resolve(rotaDoDesempenho.value).href
    : ''
);

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
  // #1429 F3 — outra gaveta (Versões, comportamento) pode ter mudado o agente: a linha da base é relida.
  if (temBase.value) baseDoAgente.recarregar();
};

// #1370 — `?gaveta=` (a volta do assistente de páginas de agendamento) vale uma vez: sai da URL
// assim que a gaveta abre, e um F5 não a reabre.
const tirarGavetaDaConsulta = () => {
  if (!route.query?.gaveta) return;
  const { gaveta, ...resto } = route.query;
  router.replace({ query: resto });
};

// Escolher o canal: atendendo, a gaveta de onde e quando; parado, a de voltar a atender (escolhe a caixa e
// liga na mesma ação). #1525 — vale também para o :tab channels da URL, por onde o módulo de Cotação e o
// cartão da lista trazem a Lia que nasceu parada: cair na gaveta só de leitura pediria mais um clique.
// #1720, com a Fase 2: o agente da equipe ligado também abre a gaveta de onde e quando.
const gavetaDoCanal = () =>
  (fase2.value ? trabalhando.value : atendendo.value)
    ? GAVETA.ONDE
    : GAVETA.VOLTAR;

const abrirDaUrl = () => {
  if (!pronto.value || !props.gaveta || props.gaveta === gavetaDaUrlAberta) {
    return;
  }
  gavetaDaUrlAberta = props.gaveta;
  abrir(props.gaveta === GAVETA.ONDE ? gavetaDoCanal() : props.gaveta);
  tirarGavetaDaConsulta();
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
// #1426 (4b) — conferências e autoteste do material: só na Fase 2 e fora da Lia (o servidor também recusa).
const conferencias = useConferenciasDoMaterial({
  agentId: () => Number(props.agentId),
});
const comConferencias = computed(() => fase2.value && !cotacao.value);
const lerConferencias = () => {
  if (comConferencias.value) conferencias.ler();
};
// A lista de materiais mudou de verdade (entrou, saiu, terminou a leitura ou a revisão): os problemas podem ter mudado.
const marcaDasFontes = computed(() =>
  listaDeFontes.value
    .map(
      fonte => `${fonte.id}:${fonte.status}:${fonte.review?.reviewed_at || ''}`
    )
    .join('|')
);
watch(marcaDasFontes, () => {
  if (comConferencias.value) conferencias.lerDepoisDaMudanca();
});

// #1426 — "N coisas no material precisam de você" no quadro: só na Fase 2, que mostra o estado real de cada material.
// Conta os cartões do "um problema por vez" e os materiais que precisam da pessoa sem cartão (ex.: reprovado na revisão
// por outro motivo).
const problemasNoMaterial = computed(() => {
  if (!fase2.value) return 0;
  const cartoes = comConferencias.value ? conferencias.problemas.value : [];
  const comCartao = new Set(cartoes.flatMap(problema => problema.fontes || []));
  const semCartao = listaDeFontes.value.filter(
    fonte => !comCartao.has(fonte.id) && precisaDeVoce(fonte)
  );
  return cartoes.length + semCartao.length;
});

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
  if (ajudante.value) ajudaDoAgente.carregar(Number(props.agentId));
  lerFontes();
  lerConferencias();
  lerPerguntas();
  if (temBase.value) baseDoAgente.carregar();
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

// #1426 (4b) — "Corrigir conversando" do cartão do autoteste abre como o "Respondeu errado?" do Testar (pergunta e
// resposta); "Escrever o que está nela" e "Explicar conversando" abrem o Mudar conversando geral.
const corrigirDoMaterial = inicial =>
  inicial ? mudar('teste', inicial) : mudar('geral');

// "Mudar conversando" da nota da gaveta Nome / Foto e nome: mesmo efeito do botão do herói.
const mudarDaGaveta = () => {
  nomeSugerido.value = '';
  mudar('geral');
};

const sairDoMudar = () => {
  vista.value = 'pagina';
  testeInicial.value = null;
  if (temBase.value) baseDoAgente.recarregar();
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

const escolherCanal = () => abrir(gavetaDoCanal());

// #1433: "Mudar" de "Onde {nome} trabalha" do agente da equipe.
const mudarEquipe = () => {
  if (!podeGerenciar.value) return;
  canais.carregar();
  aberta.value = EQUIPE;
};

// Tema 14: "Mudar" de "Quem {nome} ajuda" (passo 1) ou de "Quando chamar" (passo 2). A página só leu este
// agente: a lista da conta é lida ao abrir, para a escolha estar em dia.
const lerAgentes = async () => {
  leituraDosAgentes.value = 'carregando';
  try {
    await store.dispatch('autonomiaAgents/get');
    leituraDosAgentes.value = 'pronto';
  } catch {
    leituraDosAgentes.value = 'erro';
  }
};
const voltarInterno = async () => {
  alternando.value = true;
  try {
    await store.dispatch('autonomiaAgents/update', {
      id: agente.value.id,
      enabled: true,
      status: 'active',
    });
    useAlert(
      doInterruptor(
        t('AGENTS.JORNADA.PAGINA.VOLTAR_INTERNO.FEITO', { nome: nome.value }),
        t('AGENTS.JORNADA.AJUDANTE.INTERRUPTOR.VOLTOU', { nome: nome.value })
      )
    );
  } catch {
    useAlert(
      doInterruptor(
        t('AGENTS.JORNADA.PAGINA.VOLTAR_INTERNO.ERRO'),
        t('AGENTS.JORNADA.AJUDANTE.INTERRUPTOR.VOLTAR_ERRO')
      )
    );
  } finally {
    alternando.value = false;
  }
};

// Ligar um ajudante que não ajuda ninguém abre a escolha; salvando, ele já volta ligado.
const ligarDepoisDeEscolher = ref(false);
const mudarAjuda = (passo = 'quem', { ligar = false } = {}) => {
  if (!podeGerenciar.value) return;
  ligarDepoisDeEscolher.value = ligar;
  lerAgentes();
  ajudaDoAgente.erro.value = null;
  passoDaAjuda.value = passo;
  aberta.value = AJUDA;
};
const salvarMudancaDaAjuda = async ({ principais, quando: frase }) => {
  const feito = await ajudaDoAgente.salvar({
    agenteId: agente.value.id,
    nome: nome.value,
    principalIds: principais,
    quando: frase,
  });
  if (!feito) return;
  fechar();
  if (ligarDepoisDeEscolher.value) {
    ligarDepoisDeEscolher.value = false;
    await voltarInterno();
    return;
  }
  useAlert(t('AGENTS.JORNADA.AJUDANTE.FEITO', { nome: nome.value }));
  try {
    await store.dispatch('autonomiaAgents/show', agente.value.id);
  } catch {
    // O vínculo já foi gravado; a tela relê o agente ao abrir de novo.
  }
};

// #1366 — tirar o agente do último canal o para no servidor: relê o agente junto com as caixas, para o
// herói não continuar dizendo "Atendendo". A releitura é só para a tela; falhando, a próxima acerta.
const depoisDeMudarOnde = async () => {
  canais.carregar();
  try {
    await store.dispatch('autonomiaAgents/show', agente.value.id);
  } catch {
    // O canal já mudou; a tela relê o agente ao abrir de novo.
  }
};

const salvarMudancaDaEquipe = async ({ entram, saem }) => {
  const feito = await salvarEquipe.salvar({
    agenteId: agente.value.id,
    nome: nome.value,
    entram,
    saem,
  });
  // Falhou no meio: relê onde ele está, e a próxima tentativa manda só o que ainda falta.
  if (!feito) {
    canais.carregar();
    return;
  }
  useAlert(t('AGENTS.JORNADA.EQUIPE.FEITO', { nome: nome.value }));
  fechar();
  depoisDeMudarOnde();
};

const alternar = ligar => {
  if (!ligar) {
    dialogoParar.value?.abrir();
    return;
  }
  // Tema 14: ajudante sem ninguém para ajudar não liga "vazio": escolhe antes quem ele ajuda.
  if (ajudante.value && !quemAjuda(agente.value).length) {
    mudarAjuda('quem', { ligar: true });
    return;
  }
  if (interno.value || naEquipe.value) {
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
  useAlert(
    doInterruptor(
      t('AGENTS.JORNADA.PAGINA.PARAR.FEITO', { nome: nome.value }),
      t('AGENTS.JORNADA.AJUDANTE.INTERRUPTOR.PARAR_FEITO', { nome: nome.value })
    )
  );
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
  useAlert(t('AGENTS.JORNADA.PAGINA.EXCLUIR.FEITO', { nome: quem }));
  irParaLista();
};

// T16 → T15: "Se quiser só parar por um tempo, use Parar de atender."
const pararEmVezDeExcluir = () => {
  dialogoExcluir.value?.fechar();
  dialogoParar.value?.abrir();
};

// #1429 F3 — "Atualizar com a nova base" abre o antes e depois; só quem gerencia.
const abrirNovaBase = () => {
  if (podeGerenciar.value && temBase.value) aberta.value = BASE;
};

const baseAtualizada = () => {
  fechar();
  useAlert(t('AGENTS.JORNADA.PAGINA.BASE.FEITO', { nome: nome.value }));
};

const desfazerBase = async () => {
  if (await baseDoAgente.desfazer()) {
    useAlert(t('AGENTS.JORNADA.PAGINA.BASE.DESFEITO', { nome: nome.value }));
  }
};

const tirarPergunta = id => {
  perguntas.value = perguntas.value.filter(item => item.id !== id);
  lerFontes();
};
</script>

<template>
  <div class="w-full h-full overflow-y-auto bg-n-background">
    <div
      class="relative flex flex-col w-full gap-6 px-4 py-6 mx-auto md:px-6"
      :class="vista === 'mudar' ? 'max-w-6xl' : 'max-w-[55rem]'"
    >
      <!-- t07-carregando -->
      <template v-if="estado === ESTADO_PAGINA.CARREGANDO || excluindo">
        <h1 class="sr-only">{{ t('AGENTS.JORNADA.PAGINA.TITULO_SR') }}</h1>
        <p role="status" class="sr-only">
          {{ t('AGENTS.JORNADA.PAGINA.CARREGANDO') }}
        </p>
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
          :titulo="t('AGENTS.JORNADA.PAGINA.NAO_EXISTE')"
          :acao="t('AGENTS.JORNADA.PAGINA.VOLTAR_LISTA')"
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
          {{ t('AGENTS.JORNADA.PAGINA.VOLTAR_LISTA') }}
        </a>
        <h1 class="m-0 text-3xl font-bold text-n-slate-12">
          {{ agente?.name || t('AGENTS.JORNADA.PAGINA.TITULO_SR') }}
        </h1>
        <AgenteErro
          data-erro-abrir
          :titulo="
            agente?.name
              ? t('AGENTS.JORNADA.PAGINA.ERRO_ABRIR', { nome: agente.name })
              : t('AGENTS.JORNADA.PAGINA.ERRO_ABRIR_SEM_NOME')
          "
          :garantia="t('AGENTS.JORNADA.PAGINA.ERRO_ABRIR_GARANTIA')"
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
          :foto="foto"
          :estado="estadoDaPagina"
          :onde="ondeNoHeroi"
          :href-lista="hrefLista"
          :pode-gerenciar="podeGerenciar"
          :acao-principal="acaoPrincipal"
          :itens-mais="itensMais"
          :alternando="alternando"
          :ajudante="ajudante"
          @voltar-lista="irParaLista"
          @alternar="alternar"
          @acao-principal="acaoDoHeroi"
          @mais="escolherMais"
        />
        <p
          v-if="!trabalhando"
          data-faixa-parado
          class="flex items-start gap-3 p-4 m-0 text-sm rounded-2xl bg-n-amber-2 ring-1 ring-inset ring-n-amber-6 text-n-slate-12"
        >
          <span
            class="i-lucide-triangle-alert size-5 shrink-0 text-n-amber-11"
            aria-hidden="true"
          />
          {{ t('AGENTS.JORNADA.PAGINA.PARADO_FAIXA', { nome }) }}
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
          {{ t('AGENTS.JORNADA.PAGINA.SO_VER') }}
        </p>
        <AgenteSemana
          :numeros="semana.numerosDe(agente.id)"
          :nome="nome"
          :pode-abrir="podeGerenciar && !cotacao"
          :href-desempenho="hrefDesempenho"
          @abrir="abrir(GAVETA.CONVERSAS, { aba: $event })"
          @desempenho="router.push(rotaDoDesempenho)"
        />
        <AgenteSilencios
          :agent-id="agente.id"
          :nome="nome"
          :numeros="semana.numerosDe(agente.id)"
          :fala-com-cliente="mostraSilencios"
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
          :tambem-recebe="tambemRecebeEm.map(canal => canal.name)"
          :quantas-fontes="listaDeFontes.length"
          :quantas-perguntas="perguntas.length"
          :problemas-no-material="problemasNoMaterial"
          :equipe="equipe"
          :fase2="fase2"
          :caixas="caixas"
          :ajuda="ajuda"
          @perguntar="perguntar"
          @abrir="abrir"
          @mudar="mudar"
          @escrever="escrever"
          @escolher-canal="escolherCanal"
          @mudar-equipe="mudarEquipe"
          @mudar-ajuda="mudarAjuda"
        >
          <template #base>
            <BaseDoAgenteLinha
              v-if="mostraBase"
              :base="baseDoAgente.base.value"
              :nome="nome"
              :pode-gerenciar="podeGerenciar"
              :desfazendo="baseDoAgente.desfazendo.value"
              :erro-desfazer="baseDoAgente.erroDesfazer.value"
              :texto-erro-desfazer="baseDoAgente.textoErroDesfazer.value"
              @atualizar="abrirNovaBase"
              @desfazer="desfazerBase"
            />
          </template>
        </PaginaBlocos>
      </template>
    </div>

    <template v-if="pronto && vista === 'pagina'">
      <GavetaTestar
        v-if="aberta === GAVETA.TESTAR"
        :agente="agente"
        :nome="nome"
        :atendendo="trabalhando"
        :pode-mudar="podeMudar"
        :pergunta="perguntaDoTeste"
        :fase2="fase2"
        :pode-gerenciar="podeGerenciar"
        @fechar="fechar"
        @errado="mudar('teste', $event)"
        @ver-sabe="abrir(GAVETA.SABE)"
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
        :fase2="fase2"
        :conferencias="comConferencias ? conferencias : null"
        @fechar="fechar"
        @corrigir="corrigirDoMaterial"
        @reler="lerFontes"
        @pergunta-resolvida="tirarPergunta"
      />
      <GavetaOndeQuandoFase2
        v-else-if="
          fase2 && (aberta === GAVETA.ONDE || aberta === GAVETA.VOLTAR)
        "
        :key="aberta"
        :agente="agente"
        :nome="nome"
        :modo="aberta === GAVETA.VOLTAR ? 'voltar' : 'alterar'"
        :atendendo="trabalhando"
        :canais="canais.canais.value"
        :estado-canais="canais.estado.value"
        :atuais="atuais"
        :sem-leitura="canais.semLeitura.value"
        :horarios="horarios"
        :recebe-em-outras="recebeEmOutras"
        :equipe-atual="tambemRecebeEm.map(canal => canal.inbox_id)"
        :caixas="caixas"
        @fechar="fechar"
        @pronto="depoisDeMudarOnde"
        @reler="canais.carregar()"
        @voltar-a-atender="aberta = GAVETA.VOLTAR"
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
        :recebe-em-outras="recebeEmOutras"
        :equipe-atual="tambemRecebeEm.map(canal => canal.inbox_id)"
        :caixas="caixas"
        @fechar="fechar"
        @pronto="depoisDeMudarOnde"
        @reler="canais.carregar()"
        @voltar-a-atender="aberta = GAVETA.VOLTAR"
      />
      <AgenteGaveta
        v-else-if="aberta === EQUIPE"
        :titulo="t('AGENTS.JORNADA.ONDE.TITULO', { nome })"
        @fechar="fechar"
      >
        <EquipeCanais
          modo="mudar"
          :nome="nome"
          :agente-id="agente.id"
          :canais="canais.canais.value"
          :caixas="caixas"
          :leitura="
            canais.estado.value === 'pronto' && canais.semLeitura.value
              ? 'erro'
              : canais.estado.value
          "
          :inicial="(equipe || []).map(canal => canal.inbox_id)"
          :salvando="salvarEquipe.salvando.value"
          :erro="salvarEquipe.erro.value"
          :texto-final="t('AGENTS.JORNADA.EQUIPE.SALVAR')"
          :rotulo-carregando="t('AGENTS.JORNADA.EQUIPE.SALVANDO')"
          @voltar="fechar"
          @reler="canais.carregar()"
          @pronto="salvarMudancaDaEquipe"
        />
      </AgenteGaveta>
      <AgenteGaveta
        v-else-if="aberta === AJUDA"
        :titulo="t('AGENTS.JORNADA.AJUDANTE.QUEM_AJUDA', { nome })"
        @fechar="fechar"
      >
        <AjudantePassos
          modo="mudar"
          :nome="nome"
          :agente-id="agente.id"
          :agentes="registros || []"
          :leitura="leituraDosAgentes"
          :inicial="{
            principais: ajuda.principais.map(principal => principal.id),
            quando: ajuda.quando,
          }"
          :comecar-em="passoDaAjuda"
          :salvando="ajudaDoAgente.salvando.value"
          :erro="ajudaDoAgente.erro.value"
          :texto-final="t('AGENTS.JORNADA.EQUIPE.SALVAR')"
          :rotulo-carregando="t('AGENTS.JORNADA.EQUIPE.SALVANDO')"
          @voltar="fechar"
          @reler="lerAgentes"
          @pronto="salvarMudancaDaAjuda"
        />
      </AgenteGaveta>
      <GavetaNovaBase
        v-else-if="aberta === BASE && baseDoAgente.base.value"
        :base="baseDoAgente.base.value"
        :nome="nome"
        :comparar="baseDoAgente.comparar"
        :atualizar="baseDoAgente.atualizar"
        @fechar="fechar"
        @atualizado="baseAtualizada"
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
        :canal="canalDaFoto"
        :tem-canal="temCanal"
        :pode-mudar="podeMudar"
        @mudar="mudarDaGaveta"
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
      <GavetaAgenda
        v-else-if="aberta === GAVETA.AGENDA"
        :agente="agente"
        :nome="nome"
        :pode-mudar="podeMudar"
        @mudar="mudarDaGaveta"
        @fechar="fechar"
      />
      <GavetaFerramentas
        v-else-if="aberta === GAVETA.FERRAMENTAS"
        :agente="agente"
        :nome="nome"
        @fechar="fechar"
      />
    </template>

    <template v-if="(pronto || excluindo) && podeGerenciar">
      <DialogoAcao
        ref="dialogoParar"
        :titulo="
          doInterruptor(
            t('AGENTS.JORNADA.PAGINA.PARAR.TITULO', { nome }),
            t('AGENTS.JORNADA.AJUDANTE.INTERRUPTOR.PARAR_TITULO', { nome })
          )
        "
        :texto="
          doInterruptor(
            t('AGENTS.JORNADA.PAGINA.PARAR.TEXTO', { nome }),
            t('AGENTS.JORNADA.AJUDANTE.INTERRUPTOR.PARAR_TEXTO', { nome })
          )
        "
        :confirmar="
          doInterruptor(
            t('AGENTS.JORNADA.PAGINA.PARAR.CONFIRMAR'),
            t('AGENTS.JORNADA.AJUDANTE.INTERRUPTOR.PARAR_CONFIRMAR')
          )
        "
        :rotulo-carregando="t('AGENTS.JORNADA.PAGINA.PARAR.PARANDO')"
        :erro-titulo="
          doInterruptor(
            t('AGENTS.JORNADA.PAGINA.PARAR.ERRO'),
            t('AGENTS.JORNADA.AJUDANTE.INTERRUPTOR.PARAR_ERRO')
          )
        "
        :erro-garantia="
          doInterruptor(
            t('AGENTS.JORNADA.PAGINA.PARAR.ERRO_GARANTIA', { nome }),
            t('AGENTS.JORNADA.AJUDANTE.INTERRUPTOR.PARAR_ERRO_GARANTIA', {
              nome,
            })
          )
        "
        :executar="parar"
      />
      <DialogoAcao
        ref="dialogoExcluir"
        :titulo="t('AGENTS.JORNADA.PAGINA.EXCLUIR.TITULO', { nome })"
        :texto="t('AGENTS.JORNADA.PAGINA.EXCLUIR.TEXTO', { nome })"
        :confirmar="t('AGENTS.JORNADA.PAGINA.EXCLUIR.CONFIRMAR')"
        :rotulo-carregando="t('AGENTS.JORNADA.PAGINA.EXCLUIR.EXCLUINDO')"
        variante="perigo"
        :erro-titulo="t('AGENTS.JORNADA.PAGINA.EXCLUIR.ERRO')"
        :erro-garantia="t('AGENTS.JORNADA.PAGINA.EXCLUIR.ERRO_GARANTIA')"
        :executar="excluir"
      >
        <p v-if="trabalhando" data-extra class="m-0 text-sm text-n-slate-11">
          {{ t('AGENTS.JORNADA.PAGINA.EXCLUIR.EXTRA') }}
          <button
            data-atalho-parar
            type="button"
            class="inline-flex items-center font-semibold underline min-h-11 text-n-blue-11 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-11"
            @click="pararEmVezDeExcluir"
          >
            {{ t('AGENTS.JORNADA.PAGINA.EXCLUIR.EXTRA_ACAO') }}
          </button>
        </p>
      </DialogoAcao>
      <DialogoAcao
        ref="dialogoEscrever"
        :titulo="t('AGENTS.JORNADA.PAGINA.INSTRUCOES.AVISO_TITULO')"
        :texto="t('AGENTS.JORNADA.PAGINA.INSTRUCOES.AVISO_TEXTO', { nome })"
        :confirmar="t('AGENTS.JORNADA.PAGINA.INSTRUCOES.AVISO_CONFIRMAR')"
        variante="aviso"
        @confirmado="abrir(GAVETA.INSTRUCOES)"
      />
    </template>
  </div>
</template>
