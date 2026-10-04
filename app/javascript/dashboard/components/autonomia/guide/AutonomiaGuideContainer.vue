<script setup>
import { ref, computed, watch, nextTick, onBeforeUnmount } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import { useMapGetter } from 'dashboard/composables/store';
import { useUISettings } from 'dashboard/composables/useUISettings';
import { useWindowSize, useEventListener } from '@vueuse/core';
import { vOnClickOutside } from '@vueuse/components';
import wootConstants from 'dashboard/constants/globals';
import AutonomiaGuideAPI from 'dashboard/api/autonomiaGuide';
import CentralDeAjudaAPI from 'dashboard/api/centralDeAjuda';
import {
  useAutonomiaGuideStore,
  motivoUtilizavel,
  MAX_ANEXOS_POR_CONVERSA,
} from 'dashboard/store/modules/autonomiaGuide';
import { useLevarAteLa } from 'dashboard/composables/useLevarAteLa';
import { contextoAtual } from 'dashboard/composables/useContextoDaTela';

import GuideHeader from './GuideHeader.vue';
import GuideComposer from './GuideComposer.vue';
import GuideEtiquetaTela from './GuideEtiquetaTela.vue';
import GuideExecucao from './GuideExecucao.vue';
import { avisarContaMudou, execucaoMudouConta } from './contaMudou';
import GuideHistorico from './GuideHistorico.vue';
import GuideMemoria from './GuideMemoria.vue';
import GuideAnotei from './GuideAnotei.vue';
import GuideTarefa from './GuideTarefa.vue';
import GuideUserMessage from './GuideUserMessage.vue';
import { useAvisosDoGuia } from './useAvisosDoGuia';
import CopilotAssistantMessage from 'dashboard/components-next/copilot/CopilotAssistantMessage.vue';
import CopilotLoader from 'dashboard/components-next/copilot/CopilotLoader.vue';
import Button from 'dashboard/components-next/button/Button.vue';

// V1 — global "Guia da Plataforma" widget. Reuses the copilot presentational pieces but is NOT
// conversation-scoped: a single global thread that guides the user (onboarding/support) and, when
// the backend returns a `navigation` target, offers a button that takes the user to that screen
// (validated against the guide route allow-list + the router + the route guards). It ALSO executes
// the actions the backend proposes — but never on its own: só depois de a pessoa ler o que vai
// acontecer e clicar em confirmar.
//
// #859 — `embutido`: a mesma conversa (mesma store, mesmo backend) dentro de uma
// tela, como na de Automações. Sem cabeçalho e sem fechar; nessas telas o painel
// lateral e o lançador ficam escondidos (rota com `meta.guiaEmbutido`), para a
// conversa não aparecer duas vezes.
const props = defineProps({
  embutido: { type: Boolean, default: false },
  // [{ rotulo, pergunta }] — sugestões da tela, no lugar das gerais.
  sugestoes: { type: Array, default: null },
  introducao: { type: String, default: '' },
  // Pedido que a pessoa escolheu antes de chegar (um modelo pronto). Sai uma vez.
  pedidoInicial: { type: String, default: '' },
});
// O que o Guia fez no turno (#855), para a tela que o embute reagir; e o aviso de
// que o pedido inicial saiu, para a tela gastá-lo (#859).
const emit = defineEmits(['execucao', 'pedidoInicialEnviado']);

const { t } = useI18n();
const route = useRoute();
const router = useRouter();
const { uiSettings, updateUISettings } = useUISettings();
const currentAccount = useMapGetter('accounts/getAccount');
const accountId = useMapGetter('getCurrentAccountId');

// Tela que exige feature da conta não ganha botão quando a feature está desligada:
// o Guia nunca oferece uma tela que o backend nega. A relação tela→feature é
// gerada junto com o mapa (#534) — mantê-la à mão deixava de fora toda feature
// que alguém esquecesse de listar.
const { width: windowWidth } = useWindowSize();

const store = useAutonomiaGuideStore();
const { messages, arquivos } = store;
const { destino, acender } = useLevarAteLa();

const isSending = ref(false);
// Há pergunta esperando resposta — desta instância ou de outra (#859: a conversa
// embutida e o painel lateral são a mesma conversa). Nenhuma outra sai até ela.
const ocupado = computed(() => isSending.value || Boolean(store.pendente()));
// #895 — a mensagem de voz está virando texto; a resposta ainda não foi pedida.
const transcrevendo = ref(false);
// Os anexos que esperam no campo de digitar o próximo envio.
const pendentes = computed(() => arquivos.filter(arquivo => !arquivo.turno));
// Quantos anexos ainda cabem: o que falhou ao subir não conta.
const vagas = computed(
  () =>
    MAX_ANEXOS_POR_CONVERSA -
    arquivos.filter(arquivo => arquivo.estado !== 'erro').length
);
// Há gravação de voz no campo: nenhuma outra mensagem sai até ela ser enviada
// ou apagada — senão o áudio se perderia sem a pessoa pedir.
const gravandoVoz = ref(false);
// #861 — o histórico (conversas anteriores e "Feito pelo Guia", #855) ocupa o
// lugar da conversa enquanto aberto.
const vendoHistorico = ref(false);
// #933 — "O que eu sei" ocupa o lugar da conversa enquanto aberto.
const vendoMemoria = ref(false);

const alternarHistorico = () => {
  vendoMemoria.value = false;
  vendoHistorico.value = !vendoHistorico.value;
};

const alternarMemoria = () => {
  vendoHistorico.value = false;
  vendoMemoria.value = !vendoMemoria.value;
};

const tituloDoPainel = computed(() => {
  if (vendoMemoria.value) return t('AUTONOMIA_GUIDE.MEMORY.TITLE');
  if (vendoHistorico.value) return t('AUTONOMIA_GUIDE.HISTORY.TITLE');
  return t('AUTONOMIA_GUIDE.TITLE');
});
// #861 — reabrindo a conversa guardada. O esqueleto só aparece se demorar:
// abrir rápido não pisca uma tela de carregamento à toa.
const abrindoConversa = ref(false);
const mostrarEsqueleto = ref(false);
const falhouAoAbrir = ref(false);
const ESPERA_DO_ESQUELETO_MS = 300;
// A conta cuja conversa atual já foi pedida: abrir e fechar o painel não pede
// de novo, trocar de conta pede.
let contaCarregada = null;
const chatContainer = ref(null);
const panelRef = ref(null);

// Estados em que a ação está parada e pode (re)começar. "cancelada" entra aqui
// de propósito: "Agora não" não destrói nada — nada foi executado —, e deixá-lo
// definitivo obrigava a pessoa a reescrever a pergunta inteira só para voltar
// atrás. O texto de cancelamento continua visível, então o cartão não finge que
// o clique não aconteceu.
const ESTADOS_PARADOS = ['aguardando', 'cancelada'];

const podeConfirmar = estado => ESTADOS_PARADOS.includes(estado);
const mostraBotoes = estado => podeConfirmar(estado) || estado === 'executando';

const isSmallScreen = computed(
  () => windowWidth.value < wootConstants.SMALL_SCREEN_BREAKPOINT
);

const isEnabled = computed(
  () =>
    currentAccount.value(accountId.value)?.autonomia_guide_available === true
);

const isPanelOpen = computed(
  () => uiSettings.value.is_autonomia_guide_panel_open === true
);

// Na tela que já traz a conversa embutida, o painel lateral não abre por cima.
const telaTemGuiaEmbutido = computed(() => route?.meta?.guiaEmbutido === true);

const showPanel = computed(() => {
  if (props.embutido) return isEnabled.value;
  return isEnabled.value && isPanelOpen.value && !telaTemGuiaEmbutido.value;
});

const hasMessages = computed(() => messages.length > 0);

// #697 — ao abrir, o painel sugere os artigos da Central sobre a tela aberta (a API já
// filtra pelo papel e pelos recursos da conta). Sem artigo da tela, ou sem resposta da
// Central, ficam as sugestões gerais: a lista nunca aparece vazia.
const MAX_SUGESTOES_DA_TELA = 3;
const artigosDaCentral = ref([]);
let centralPedida = false;

const carregarCentral = async () => {
  if (centralPedida) return;
  centralPedida = true;
  try {
    const { data } = await CentralDeAjudaAPI.get();
    artigosDaCentral.value = (data?.capitulos || []).flatMap(
      capitulo => capitulo.artigos || []
    );
  } catch {
    // tenta de novo na próxima abertura; até lá valem as sugestões gerais
    centralPedida = false;
  }
};

const sugestoesGerais = computed(() =>
  [
    t('AUTONOMIA_GUIDE.SUGGESTIONS.KANBAN'),
    t('AUTONOMIA_GUIDE.SUGGESTIONS.WHATSAPP'),
    t('AUTONOMIA_GUIDE.SUGGESTIONS.REPORTS'),
  ].map(texto => ({ rotulo: texto, pergunta: texto }))
);

const sugestoesDaTela = computed(() =>
  artigosDaCentral.value
    .filter(artigo => artigo.rota && artigo.rota === route.name)
    .slice(0, MAX_SUGESTOES_DA_TELA)
    .map(artigo => ({
      rotulo: artigo.titulo,
      pergunta: t('AUTONOMIA_GUIDE.SUGGESTION_ARTICLE', {
        titulo: artigo.titulo,
      }),
    }))
);

const suggestions = computed(() => {
  if (props.sugestoes?.length) return props.sugestoes;
  return sugestoesDaTela.value.length
    ? sugestoesDaTela.value
    : sugestoesGerais.value;
});

watch(
  showPanel,
  aberto => {
    if (aberto) carregarCentral();
  },
  { immediate: true }
);

const scrollToBottom = async () => {
  await nextTick();
  if (chatContainer.value) {
    chatContainer.value.scrollTop = chatContainer.value.scrollHeight;
  }
};

const closePanel = () => {
  updateUISettings({
    is_autonomia_guide_panel_open: false,
    is_contact_sidebar_open: false,
  });
};

// A confirmação de apagar uma conversa (#861) abre fora do painel; clicar
// nela não é clicar fora do Guia.
const handleClickOutside = () => {
  if (document.querySelector('dialog[open]')) return;
  if (props.embutido) return;
  if (isSmallScreen.value && isPanelOpen.value) closePanel();
};

// Resolve a backend `navigation` to a real router location, or null. Defense-in-depth: the route must
// be in the guide allow-list AND resolve cleanly (router.resolve THROWS on a missing required param,
// so a screen of ONE record without its id renders NO button instead of a dead one). The ids come
// from the model, which read the account (#590). The route guards still enforce the user's
// permission on push.
const navLocation = nav => destino(nav?.route_name, nav?.params);

// #636 — até 5 telas por resposta, na ordem em que o Guia escolheu. O store já normaliza
// `navigations` (lista nova ou singular antigo, embrulhado) — aqui só falta filtrar pelas que o
// roteador resolve de verdade (mesma defesa de `navLocation`, item a item).
//
// Calculado UMA VEZ por mensagem (revisão #637 do PR), não a cada leitura do template: o `v-for`
// do template chama isto várias vezes por render (no `v-if` do bloco, de novo em cada botão, nos
// dois layouts), e recalcular `router.resolve` a cada chamada é trabalho repetido à toa. A chave é
// o próprio objeto do registro — imutável depois de criado — e ele nunca muda de conta no meio da
// vida (troca de conta reseta o thread inteiro, `watch(accountId, () => store.reset())`).
const telasValidasCache = new WeakMap();
const telasValidas = item => {
  if (telasValidasCache.has(item)) return telasValidasCache.get(item);

  const valor = (item.navigations || [])
    .map(nav => ({ nav, alvo: navLocation(nav) }))
    .filter(entrada => entrada.alvo);
  telasValidasCache.set(item, valor);
  return valor;
};

// Duas aparências (#636). Com no máximo uma tela e um artigo, o painel fica como sempre foi: um
// botão de cada, rótulo fixo. Com mais de um item em qualquer lista, vira duas seções — "Ir
// para" (botões) e "Para ler com calma" (links) — uma entrada por item, com o nome dela.
const layoutMultiplo = item =>
  telasValidas(item).length > 1 || (item.artigos || []).length > 1;

const chaveDaTela = nav =>
  `${nav.route_name}:${JSON.stringify(nav.params || {})}`;

// Esta função não age sobre nada: só move a pessoa até a tela e (V2) destaca o
// elemento de lá. Quem executa ação é `confirmarAcao`, mais abaixo.
const navigateTo = nav => {
  const target = navLocation(nav);
  if (!target) return;
  router.push(target);
  if (nav.highlight) {
    // Close the chat panel so the highlighted element is fully visible (the right-docked panel would
    // otherwise cover right-aligned action buttons). Trigger AFTER the close transition so the element
    // is at its final position. The thread is preserved — reopening the Guia shows it again.
    closePanel();
    acender(nav.highlight);
  } else if (isSmallScreen.value) {
    closePanel();
  }
};

// O botão "ler o artigo completo" (#617) não passa pela guarda de rota da
// tela (`destino`/`isGuideRoute`): ele não é uma tela DA CONTA que a permissão
// de alguém restrinja, é o mesmo artigo que a ferramenta já leu com a
// permissão de quem perguntou. Abre sempre que o Guia leu um.
const abrirArtigo = artigo => {
  router.push({
    name: 'central_de_ajuda_artigo',
    params: { accountId: accountId.value, ref: artigo.ref },
  });
};

// O cartão da ação é o único lugar onde o desfecho aparece. Quando ele já não
// existe — a pessoa trocou de conta ou clicou em "Nova conversa" durante os
// segundos da execução —, a ação JÁ rodou no servidor e o resultado não pode
// simplesmente sumir: vira alerta.
const entregarDesfecho = ({ conta, id, estado, resultado, avisoSeSumiu }) => {
  const mesmaConta = accountId.value === conta;
  if (mesmaConta && store.marcarAcao(id, estado, resultado)) return;
  useAlert(avisoSeSumiu);
};

// A execução acontece aqui, e só aqui: depois de a pessoa ler a descrição e
// clicar em confirmar. O backend recusa de novo o que estiver fora do catálogo.
const confirmarAcao = async item => {
  // Porta de entrada única: `marcarAcao` muda o estado de forma síncrona, então
  // o segundo clique de um duplo-clique já encontra 'executando' e volta sem
  // disparar um segundo POST. Antes, dois cliques criavam dois registros.
  if (!podeConfirmar(item.acaoEstado)) return;
  // Mesma proteção de conta que o chat tem: a resposta pode levar segundos, e
  // o desfecho não pode cair na conversa de outra conta.
  const conta = accountId.value;
  store.marcarAcao(item.id, 'executando');
  try {
    const { data } = await AutonomiaGuideAPI.executarAcao({
      acao: item.acao.nome,
      dados: item.acao.dados,
      pedidoId: item.pedidoId,
    });
    avisarContaMudou();
    entregarDesfecho({
      conta,
      id: item.id,
      estado: 'feita',
      resultado: data.mensagem,
      avisoSeSumiu: t('AUTONOMIA_GUIDE.ACTION.LOST'),
    });
  } catch (error) {
    // #861 — já foi feita em outra aba ou aparelho: o servidor não repete e
    // devolve o resultado guardado. O cartão mostra feita, sem botões.
    const corpo = error?.response?.data;
    if (corpo?.acao_estado === 'feita') {
      entregarDesfecho({
        conta,
        id: item.id,
        estado: 'feita',
        resultado: corpo.mensagem,
        avisoSeSumiu: t('AUTONOMIA_GUIDE.ACTION.LOST'),
      });
      return;
    }
    const texto =
      motivoUtilizavel(corpo?.error) ||
      t('AUTONOMIA_GUIDE.ACTION.FAILED_GENERIC');
    entregarDesfecho({
      conta,
      id: item.id,
      estado: 'falhou',
      resultado: texto,
      // Aqui a ação não rodou, então o aviso é o próprio motivo da falha —
      // dizer "executou mas você saiu" seria mentira.
      avisoSeSumiu: texto,
    });
  }
};

// #572 — o Guia responde num job, e a tela busca a resposta. Antes ela vinha da
// própria requisição, que o servidor mata aos 15 segundos: pergunta que pedia
// duas leituras morria com erro 500.
//
// A janela acompanha o TTL de 30 minutos do pedido no servidor, para a tela
// nunca desistir de uma resposta que ainda vai chegar.
const ESPERA_ENTRE_BUSCAS_MS = 1500;
const MAX_BUSCAS = Math.floor((30 * 60 * 1000) / ESPERA_ENTRE_BUSCAS_MS);
const PENDENTE = 'pending';
const PRONTO = 'done';

const esperar = ms =>
  new Promise(resolve => {
    setTimeout(resolve, ms);
  });

// Quem desmonta o painel não quer mais a resposta.
let desmontado = false;
let requestSequence = 0;
// Cada instância (o painel lateral e a conversa embutida numa tela) tem um
// crachá; é com ele que ela segura e solta a pergunta pendente na store.
const cracha = Symbol('guia');
onBeforeUnmount(() => {
  desmontado = true;
  // A conversa embutida é a mesma do painel lateral (#859): sair da tela não
  // apaga o que a pessoa conversou, ela continua no painel — e a pergunta que
  // ainda esperava resposta fica solta para o painel terminar de buscar.
  if (props.embutido) {
    store.soltarPendente(cracha);
    return;
  }
  // Solta o áudio e as miniaturas que estavam na memória do navegador.
  store.reset();
});

// Recursiva, e não um laço: cada busca espera a anterior, e a próxima só sai
// depois do intervalo — nunca duas no ar ao mesmo tempo.
//
// Para sozinha quando a resposta deixou de interessar: o painel saiu da tela,
// ou a pessoa trocou de conta. Sem isso a tela seguiria consultando por até
// trinta minutos uma resposta que não ia mostrar a ninguém. -> null quando parou.
const buscarResposta = async (id, requestAccount, requestId, tentativa = 0) => {
  if (
    tentativa >= MAX_BUSCAS ||
    desmontado ||
    requestId !== requestSequence ||
    accountId.value !== requestAccount
  )
    return tentativa >= MAX_BUSCAS ? { status: 'failed' } : null;
  await esperar(ESPERA_ENTRE_BUSCAS_MS);
  if (
    desmontado ||
    requestId !== requestSequence ||
    accountId.value !== requestAccount
  )
    return null;
  const { data } = await AutonomiaGuideAPI.resposta(id);
  if (
    desmontado ||
    requestId !== requestSequence ||
    accountId.value !== requestAccount
  )
    return null;
  if (data.status !== PENDENTE) return data;
  return buscarResposta(id, requestAccount, requestId, tentativa + 1);
};

// A falha fica ESCRITA na conversa. Antes era um aviso que sumia sozinho em
// poucos segundos: quem olhava para a tela depois via a pergunta sem resposta
// nenhuma, e não tinha como saber que devia tentar de novo.
const avisarFalha = () =>
  store.addAssistantMessage({ content: t('AUTONOMIA_GUIDE.ERROR') });

// A resposta ainda interessa: o painel está na tela, na mesma conta e na
// mesma vez de pergunta.
const aindaInteressa = (conta, vez) =>
  !desmontado && vez === requestSequence && accountId.value === conta;

// Uma resposta que já chegou: entra na conversa, e a tela que embute o Guia
// fica sabendo o que ele fez (#859).
const entregarResposta = (data, pedidoId) => {
  if (data.status !== PRONTO) {
    avisarFalha();
  } else if (data.available && data.text) {
    store.addAssistantMessage({
      content: data.text,
      navigation: data.navigation || null,
      navigations: data.navigations || null,
      acao: data.acao || null,
      artigo: data.artigo || null,
      artigos: data.artigos || null,
      execucao: data.execucao || null,
      lembrancas: data.lembrancas || null,
      tarefa: data.tarefa || null,
      pedidoId,
    });
    if (data.execucao) emit('execucao', data.execucao);
    if (execucaoMudouConta(data.execucao)) avisarContaMudou();
  } else if (data.retido) {
    // O Guia está no ar, mas não devolveu resposta. Dizer "indisponível" faria
    // a pessoa achar que o produto caiu; o texto pede para perguntar de novo,
    // sem oferecer suporte (#914). O que ele já fez neste turno aparece mesmo
    // assim (#855): mudou a conta.
    store.addAssistantMessage({
      content: t('AUTONOMIA_GUIDE.WITHHELD'),
      execucao: data.execucao || null,
      tarefa: data.tarefa || null,
    });
    if (data.execucao) emit('execucao', data.execucao);
    if (execucaoMudouConta(data.execucao)) avisarContaMudou();
  } else {
    useAlert(t('AUTONOMIA_GUIDE.UNAVAILABLE'));
  }
};

// Busca a resposta de um pedido que o servidor já aceitou. Se esta instância
// sair da tela no meio, ela para — e a pergunta continua pendente na store,
// solta, para o painel lateral adotar (#859).
const acompanharResposta = async ({ id, chave, requestAccount, requestId }) => {
  try {
    const data = await buscarResposta(id, requestAccount, requestId);
    if (!data || !aindaInteressa(requestAccount, requestId)) return;
    store.fecharPendente(chave);
    entregarResposta(data, id);
  } catch {
    if (!aindaInteressa(requestAccount, requestId)) return;
    store.fecharPendente(chave);
    avisarFalha();
  } finally {
    if (requestId === requestSequence) isSending.value = false;
  }
};

// #861 — o que o balão mostrou de anexo, para a conversa reabrir igual.
const anexosDe = registro =>
  (registro?.anexos || []).map(({ nome, tipo }) => ({ nome, tipo }));

// #861 — a conversa da tela pode não existir mais no servidor: apagada em
// outra aba ou pelo próprio Guia. O 404 dela não pode
// virar "não consegui" para sempre: a pergunta abre uma conversa nova, levando
// o que está na tela como histórico. Sem conversa aberta, o 404 é o Guia fora
// do ar para a conta, e não se repete.
const abrirPedidoNoServidor = async (chave, payload) => {
  try {
    return await AutonomiaGuideAPI.chat(payload);
  } catch (error) {
    const conversaSumiu =
      error?.response?.status === 404 && Boolean(payload.conversaId);
    if (!conversaSumiu || !store.pendenteAtivo(chave)) throw error;
    store.definirConversa(null);
    return AutonomiaGuideAPI.chat({ ...payload, conversaId: null });
  }
};

// #934 — o que a pessoa vê na tela vai junto da pergunta. O × da etiqueta tira
// só da próxima; na seguinte, a etiqueta volta.
const telaAtual = computed(() => contextoAtual(route));
const semTelaNaProxima = ref(false);
const telaDaPergunta = () => {
  const tela = semTelaNaProxima.value ? undefined : telaAtual.value;
  semTelaNaProxima.value = false;
  return tela;
};

const requestReply = async (requestAccount, message, requestId, registro) => {
  const chave = store.abrirPendente(requestAccount, cracha);
  let pedido;
  try {
    ({ data: pedido } = await abrirPedidoNoServidor(chave, {
      message,
      history: store.toHistory(),
      routeContext: route.name,
      // #859 — o registro aberto (ex.: a automação 42); o servidor guarda só números.
      routeParams: route.params,
      tela: telaDaPergunta(),
      arquivos: store.arquivosProntos(),
      conversaId: store.conversaAtual(),
      anexos: anexosDe(registro),
    }));
  } catch {
    // A pergunta nem chegou ao servidor. A falha fica escrita na conversa, mesmo
    // que esta tela já tenha saído: a conversa é a mesma do painel lateral.
    if (store.pendenteAtivo(chave)) avisarFalha();
    store.fecharPendente(chave);
    if (requestId === requestSequence) isSending.value = false;
    return;
  }
  // A primeira pergunta abre a conversa no servidor; as seguintes a continuam.
  // Vale mesmo que a tela embutida tenha saído: a conversa é a mesma (#859).
  if (pedido.conversa_id && store.pendenteAtivo(chave)) {
    store.definirConversa(pedido.conversa_id);
  }
  store.registrarPedidoPendente(chave, pedido.id);
  if (!aindaInteressa(requestAccount, requestId)) return;
  await acompanharResposta({ id: pedido.id, chave, requestAccount, requestId });
};

// #861 — a conversa reaberta tinha uma pergunta ainda sem resposta: o pedido
// segue valendo no servidor (30 minutos), e a tela volta a buscar. Ela entra
// na store como pendente (#859): se esta tela sair, o painel lateral adota.
const retomarPendente = (pedidoId, conta) => {
  const chave = store.abrirPendente(conta, cracha);
  store.registrarPedidoPendente(chave, pedidoId);
  requestSequence += 1;
  isSending.value = true;
  acompanharResposta({
    id: pedidoId,
    chave,
    requestAccount: conta,
    requestId: requestSequence,
  });
};

const avisosDoTurno = () => ({
  retido: t('AUTONOMIA_GUIDE.WITHHELD'),
  falhou: t('AUTONOMIA_GUIDE.ERROR'),
});

// #861 — põe uma conversa guardada na tela. `carregar` é a chamada à API (a
// atual ou uma da lista). Falhou: `aoFalhar` decide o que a pessoa vê, e a
// conversa que estava na tela continua lá.
const abrirConversa = async (carregar, aoFalhar) => {
  const conta = accountId.value;
  requestSequence += 1;
  const vez = requestSequence;
  // A pergunta que esperava resposta era da conversa que sai da tela (#859).
  const perguntaAnterior = store.pendente();
  if (perguntaAnterior) store.fecharPendente(perguntaAnterior.chave);
  isSending.value = false;
  transcrevendo.value = false;
  abrindoConversa.value = true;
  falhouAoAbrir.value = false;
  const esqueleto = setTimeout(() => {
    if (vez === requestSequence) mostrarEsqueleto.value = true;
  }, ESPERA_DO_ESQUELETO_MS);
  try {
    const { data } = await carregar();
    if (!aindaInteressa(conta, vez)) return;
    contaCarregada = conta;
    // Nenhuma conversa guardada: fica a tela de começo, com o que já estiver
    // no campo de digitar.
    if (!data?.id) return;
    const pendente = store.hidratar(data, avisosDoTurno());
    if (pendente) retomarPendente(pendente, conta);
  } catch {
    if (aindaInteressa(conta, vez)) aoFalhar();
  } finally {
    clearTimeout(esqueleto);
    if (accountId.value === conta) {
      abrindoConversa.value = false;
      mostrarEsqueleto.value = false;
    }
  }
};

// Ao abrir o painel, a conversa de antes volta. Quem já está conversando (o
// painel foi só fechado e reaberto) não perde nada. A conversa embutida (página
// de Automações, #859) começa limpa: não traz a conversa guardada de volta.
const reabrirConversaAtual = () => {
  if (props.embutido) return;
  if (contaCarregada === accountId.value) return;
  if (hasMessages.value) {
    contaCarregada = accountId.value;
    return;
  }
  abrirConversa(
    () => AutonomiaGuideAPI.conversaAtual(),
    () => {
      falhouAoAbrir.value = true;
    }
  );
};

const abrirDoHistorico = id => {
  vendoHistorico.value = false;
  abrirConversa(
    () => AutonomiaGuideAPI.conversa(id),
    () => useAlert(t('AUTONOMIA_GUIDE.HISTORY.OPEN_FAILED'))
  );
};

// "Nova conversa" só esquece a conversa na tela: a anterior continua guardada
// e aparece no histórico.
const resetConversation = () => {
  requestSequence += 1;
  isSending.value = false;
  transcrevendo.value = false;
  falhouAoAbrir.value = false;
  contaCarregada = accountId.value;
  store.reset();
};

// Apagou a conversa que estava aberta: o painel começa outra.
const conversaApagada = id => {
  if (id === store.conversaAtual()) resetConversation();
};

// #857 — sobe o arquivo e o deixa na conversa. O erro aparece no próprio
// arquivo e num aviso com o motivo da plataforma (tipo ou tamanho).
// #895 — foto ganha miniatura, mostrada no campo e depois no balão.
const avisarLimiteDeAnexos = () =>
  useAlert(t('AUTONOMIA_GUIDE.FILE.LIMIT', { max: MAX_ANEXOS_POR_CONVERSA }));

const anexarArquivo = async file => {
  if (vagas.value <= 0) {
    avisarLimiteDeAnexos();
    return;
  }
  const conta = accountId.value;
  const ehFoto = (file.type || '').startsWith('image/');
  const id = store.addArquivo(file.name, {
    tipo: ehFoto ? 'imagem' : 'documento',
    previa: ehFoto ? URL.createObjectURL(file) : null,
  });
  try {
    const { data } = await AutonomiaGuideAPI.enviarArquivo(file);
    if (accountId.value !== conta) return;
    store.marcarArquivo(id, 'pronto', data.signed_id);
  } catch (error) {
    if (accountId.value !== conta) return;
    store.marcarArquivo(id, 'erro');
    useAlert(
      motivoUtilizavel(error?.response?.data?.error) ||
        t('AUTONOMIA_GUIDE.FILE.FAILED')
    );
  }
};

// Abre a vez de uma pergunta: prende a conta e o número do pedido. Se a pessoa
// trocar de conta antes da resposta, ela não cai na conversa da outra conta.
const abrirPedido = () => {
  requestSequence += 1;
  vendoHistorico.value = false;
  vendoMemoria.value = false;
  // Perguntar depois de a conversa antiga não abrir começa uma nova.
  falhouAoAbrir.value = false;
  isSending.value = true;
  return { conta: accountId.value, pedido: requestSequence };
};

// #859 — pergunta que outra instância soltou ao sair da tela (a conversa
// embutida). Quem estiver montado e na mesma conta termina de buscar a resposta.
const adotarPendente = () => {
  if (desmontado || !isEnabled.value) return;
  const adotado = store.adotarPendente(accountId.value, cracha);
  if (!adotado) return;
  requestSequence += 1;
  isSending.value = true;
  acompanharResposta({
    id: adotado.id,
    chave: adotado.chave,
    requestAccount: accountId.value,
    requestId: requestSequence,
  });
};

watch(
  () => {
    const pendente = store.pendente();
    return pendente ? `${pendente.chave}:${pendente.id}:${!pendente.dono}` : '';
  },
  adotarPendente,
  { immediate: true }
);

const podeEnviar = () => {
  if (ocupado.value) {
    // Antes a segunda pergunta não fazia nada e não avisava nada.
    useAlert(t('AUTONOMIA_GUIDE.SENDING'));
    return false;
  }
  return true;
};

// GuideComposer clears the field only when this returns true. Accept = the question is in the
// thread, so return right away and let the reply load behind the loader; false keeps the text.
// #895 — só anexos, sem texto, também vale: o balão mostra os anexos e o Guia
// recebe uma frase padrão (o servidor não responde a pergunta vazia).
const sendMessage = message => {
  if (gravandoVoz.value) {
    useAlert(t('AUTONOMIA_GUIDE.VOICE.FINISH_FIRST'));
    return false;
  }
  const temTexto = Boolean(message?.trim());
  const prontos = pendentes.value.filter(item => item.estado === 'pronto');
  if (!temTexto && !prontos.length) return false;
  if (pendentes.value.some(item => item.estado === 'subindo')) {
    useAlert(t('AUTONOMIA_GUIDE.FILE.WAIT'));
    return false;
  }
  if (!podeEnviar()) return false;
  const conteudo = temTexto
    ? message
    : t('AUTONOMIA_GUIDE.FILE.DEFAULT_MESSAGE');
  const { conta, pedido } = abrirPedido();
  const registro = store.addUserMessage(conteudo, {
    texto: temTexto ? message : '',
  });
  requestReply(conta, conteudo, pedido, registro);
  return true;
};

// #895 — a mensagem de voz vira texto aqui, e só com o texto o Guia é
// chamado. Falhou: o balão mostra o erro e o "Tentar de novo"; nada é pedido.
const transcreverMensagem = async (registro, conta, pedido) => {
  const ainda = () =>
    !desmontado && pedido === requestSequence && accountId.value === conta;
  transcrevendo.value = true;
  let texto = '';
  let erro = '';
  try {
    const { data } = await AutonomiaGuideAPI.transcrever(registro.voz.audio);
    texto = (data?.texto || '').trim();
  } catch (error) {
    erro = motivoUtilizavel(error?.response?.data?.error);
  }
  if (!ainda()) return;
  transcrevendo.value = false;
  if (!texto) {
    store.marcarVoz(registro.id, 'erro', {
      erro: erro || t('AUTONOMIA_GUIDE.VOICE.FAILED'),
    });
    isSending.value = false;
    return;
  }
  if (!store.marcarVoz(registro.id, 'pronta', { texto })) return;
  requestReply(conta, texto, pedido, registro);
};

const enviarVoz = ({ audio, duracao }) => {
  if (!podeEnviar()) return false;
  const { conta, pedido } = abrirPedido();
  const registro = store.addUserMessage('', {
    voz: { audio, url: URL.createObjectURL(audio), duracao },
  });
  transcreverMensagem(registro, conta, pedido);
  return true;
};

const tentarVozDeNovo = item => {
  if (item.voz?.estado !== 'erro') return;
  if (gravandoVoz.value) {
    useAlert(t('AUTONOMIA_GUIDE.VOICE.FINISH_FIRST'));
    return;
  }
  if (!podeEnviar()) return;
  const { conta, pedido } = abrirPedido();
  store.marcarVoz(item.id, 'transcrevendo');
  transcreverMensagem(item, conta, pedido);
};

// Só o número de mensagens não basta: o desfecho da ação ("Pronto, feito.")
// entra num cartão que já existe, sem criar mensagem nenhuma, e ficava abaixo
// da dobra. A assinatura abaixo muda também quando o estado da ação muda.
const scrollSignal = computed(() =>
  messages
    .map(
      item =>
        `${item.id}:${item.acaoEstado || ''}:${item.acaoResultado || ''}:${item.voz?.estado || ''}`
    )
    .join('|')
);

watch([scrollSignal, ocupado], () => scrollToBottom());

// Esc fecha o painel de onde quer que o foco esteja (o painel é uma região
// lateral, não um modal, então o foco pode estar fora dele).
useEventListener(document, 'keydown', event => {
  if (props.embutido || event.key !== 'Escape' || !showPanel.value) return;
  closePanel();
});

// Ao abrir, o foco vai para a região — que tem nome — em vez de continuar no
// lançador, que some. Fechar devolve o foco ao lançador, e isso é feito lá,
// quando ele reaparece.
watch(showPanel, async aberto => {
  if (!aberto || props.embutido) return;
  await nextTick();
  panelRef.value?.focus();
});

// #935 — com aviso novo, abrir o painel traz a conversa do servidor (o aviso é
// um turno dela) e marca os avisos como vistos. Com o painel aberto, o aviso que
// chega pelo ActionCable entra do mesmo jeito. Pergunta em curso não é cortada:
// o aviso espera a próxima abertura.
const { quantidade: avisosNovos, marcarVistos } = useAvisosDoGuia();
const trazerAvisos = async () => {
  if (props.embutido || isSending.value) return;
  await abrirConversa(
    () => AutonomiaGuideAPI.conversaAtual(),
    () => {
      falhouAoAbrir.value = true;
    }
  );
  marcarVistos();
};

// #861 — abrir o painel reabre a conversa guardada. Aqui embaixo, e não junto
// do `watch` da Central: precisa de tudo o que a conversa usa já definido.
watch(
  showPanel,
  aberto => {
    if (!aberto) return;
    if (avisosNovos.value > 0 && !props.embutido) trazerAvisos();
    else reabrirConversaAtual();
  },
  { immediate: true }
);

watch(avisosNovos, novos => {
  if (novos > 0 && showPanel.value) trazerAvisos();
});

// #944 — o link do push e do e-mail do aviso urgente (`?guia=aviso`) abre o
// painel, que reabre a conversa do aviso. O parâmetro sai do endereço: recarregar
// a página não abre o Guia de novo.
watch(
  () => route?.query?.guia,
  guia => {
    if (props.embutido || !guia) return;
    updateUISettings({
      is_autonomia_guide_panel_open: true,
      is_autonomia_copilot_panel_open: false,
      is_contact_sidebar_open: false,
    });
    const query = Object.fromEntries(
      Object.entries(route.query).filter(([chave]) => chave !== 'guia')
    );
    router.replace({ query });
  },
  { immediate: true }
);

// The guide thread is a global module-level singleton; clear it when switching accounts so the
// previous account's conversation never lingers on screen for a different account/operator.
watch(accountId, () => {
  requestSequence += 1;
  isSending.value = false;
  transcrevendo.value = false;
  vendoHistorico.value = false;
  vendoMemoria.value = false;
  falhouAoAbrir.value = false;
  abrindoConversa.value = false;
  mostrarEsqueleto.value = false;
  contaCarregada = null;
  store.reset();
  if (showPanel.value) reabrirConversaAtual();
});

// #859 — o modelo pronto que a pessoa escolheu na lista vira a primeira pergunta,
// uma vez só. Espera a conta dizer que o Guia está ligado.
let pedidoInicialEnviado = false;
watch(
  isEnabled,
  ligado => {
    if (!ligado || !props.pedidoInicial || pedidoInicialEnviado) return;
    pedidoInicialEnviado = true;
    if (sendMessage(props.pedidoInicial)) emit('pedidoInicialEnviado');
  },
  { immediate: true }
);

const classeDoPainel = computed(() =>
  props.embutido
    ? 'bg-n-surface-2 h-full w-full overflow-hidden flex rounded-xl border border-n-weak'
    : 'bg-n-surface-2 h-full overflow-hidden flex-col fixed top-0 ltr:right-0 rtl:left-0 z-40 w-full max-w-sm transition-transform duration-300 ease-in-out md:static md:w-[320px] md:min-w-[320px] ltr:border-l rtl:border-r border-n-weak 2xl:min-w-[360px] 2xl:w-[360px] shadow-lg md:shadow-none flex focus:outline-none'
);
</script>

<template>
  <div
    v-if="showPanel"
    ref="panelRef"
    v-on-click-outside="handleClickOutside"
    :role="embutido ? 'region' : 'complementary'"
    :tabindex="embutido ? undefined : -1"
    :aria-label="$t('AUTONOMIA_GUIDE.A11Y.PANEL')"
    :class="classeDoPainel"
  >
    <div class="flex flex-col h-full text-sm leading-6 tracking-tight w-full">
      <GuideHeader
        v-if="!embutido"
        :title="tituloDoPainel"
        :can-reset="hasMessages && !vendoHistorico && !vendoMemoria"
        :vendo-historico="vendoHistorico"
        :vendo-memoria="vendoMemoria"
        @reset="resetConversation"
        @historico="alternarHistorico"
        @memoria="alternarMemoria"
        @close="closePanel"
      />

      <div v-if="vendoHistorico" class="flex-1 flex px-4 py-4 overflow-y-auto">
        <GuideHistorico
          :conversa-atual="store.conversaAtual()"
          @abrir="abrirDoHistorico"
          @apagou="conversaApagada"
        />
      </div>

      <div
        v-else-if="vendoMemoria"
        class="flex-1 flex px-4 py-4 overflow-y-auto"
      >
        <GuideMemoria @perguntar="sendMessage" />
      </div>

      <div
        v-show="!vendoHistorico && !vendoMemoria"
        ref="chatContainer"
        role="log"
        aria-live="polite"
        :aria-busy="ocupado ? 'true' : 'false'"
        :aria-label="$t('AUTONOMIA_GUIDE.A11Y.LOG')"
        class="flex-1 flex px-4 py-4 overflow-y-auto items-start"
      >
        <!-- #861 — reabrindo a conversa guardada: dois balões de esqueleto. -->
        <div
          v-if="mostrarEsqueleto"
          data-esqueleto
          class="flex-1 flex flex-col gap-6 w-full"
          role="status"
        >
          <span class="sr-only">{{
            $t('AUTONOMIA_GUIDE.HISTORY.OPENING')
          }}</span>
          <div
            class="self-end h-10 w-2/3 rounded-2xl bg-n-alpha-2 animate-pulse"
          />
          <div class="h-20 w-5/6 rounded-2xl bg-n-alpha-1 animate-pulse" />
        </div>
        <div
          v-else-if="falhouAoAbrir"
          data-falhou-ao-abrir
          class="flex-1 flex flex-col items-start gap-3 px-1 py-2"
        >
          <p class="mb-0 text-sm text-n-slate-12">
            {{ $t('AUTONOMIA_GUIDE.HISTORY.REOPEN_FAILED') }}
          </p>
          <Button
            :label="$t('AUTONOMIA_GUIDE.HISTORY.START_NEW')"
            icon="i-lucide-message-circle-plus"
            blue
            faded
            class="min-h-11"
            @click="resetConversation"
          />
        </div>
        <div
          v-else-if="hasMessages"
          class="space-y-6 flex-1 flex flex-col w-full"
        >
          <template v-for="(item, index) in messages" :key="item.id">
            <GuideUserMessage
              v-if="item.message_type === 'user'"
              :item="item"
              @tentar-de-novo="tentarVozDeNovo(item)"
            />
            <div v-else class="flex flex-col gap-2 w-full">
              <!-- #935 — o Guia falou primeiro: um aviso do que ele mediu na conta. -->
              <span
                v-if="item.aviso"
                data-aviso
                class="inline-flex items-center self-start gap-1 px-2 py-0.5 rounded-full bg-n-amber-3 text-n-amber-11 text-xs font-medium"
              >
                <span class="i-lucide-bell-ring size-3" aria-hidden="true" />
                {{ $t('AUTONOMIA_GUIDE.AVISOS.SELO') }}
              </span>
              <CopilotAssistantMessage
                :message="item.message"
                :is-last-message="index === messages.length - 1"
                :sender-name="$t('AUTONOMIA_GUIDE.TITLE')"
              />
              <!-- O que o Guia já fez neste turno, com o desfazer (#855). -->
              <GuideExecucao v-if="item.execucao" :execucao="item.execucao" />
              <!-- #936 — o trabalho grande planejado neste turno: amostra, andamento e relatório. -->
              <GuideTarefa v-if="item.tarefa" :tarefa-id="item.tarefa.id" />
              <!-- #933 — o que o Guia anotou neste turno, com "Esquecer". -->
              <GuideAnotei
                v-for="lembranca in item.lembrancas || []"
                :key="lembranca.id"
                :lembranca="lembranca"
                @esqueceu="store.esquecerLembranca(item.id, $event)"
              />
              <!-- Ação que não tem volta: a pessoa lê o que vai acontecer, com
                   os valores, e só então confirma. Nada executa antes disso. -->
              <div
                v-if="item.acao"
                class="rounded-lg border border-n-weak bg-n-alpha-1 p-3 flex flex-col gap-2"
              >
                <p class="mb-0 text-sm break-words text-n-slate-12">
                  {{ item.acao.descricao.frase }}
                </p>
                <!-- O pedido literal, sempre visível: a frase acima pode
                     suavizar, isto não. É o que torna a confirmação informada —
                     por isso não fica no menor texto do cartão. -->
                <p class="mb-0 text-sm break-words text-n-slate-11">
                  {{ item.acao.descricao.detalhe }}
                </p>
                <p
                  v-if="item.acao.descricao.aviso"
                  class="mb-0 text-sm font-medium break-words text-n-ruby-11"
                >
                  {{ item.acao.descricao.aviso }}
                </p>
                <!-- Cada estado tem o seu próprio ramo, nomeado. A primeira
                     versão usava `v-else` para "cancelada", então o estado
                     "executando" caía nele: quem clicava em Confirmar lia
                     "Você cancelou esta ação" enquanto a ação rodava. -->
                <p
                  v-if="item.acaoEstado === 'executando'"
                  class="flex items-center gap-2 mb-0 text-sm text-n-slate-11"
                >
                  <span class="i-svg-spinner size-4 shrink-0" />
                  {{ $t('AUTONOMIA_GUIDE.ACTION.RUNNING') }}
                </p>
                <p
                  v-else-if="item.acaoEstado === 'cancelada'"
                  class="mb-0 text-sm text-n-slate-11"
                >
                  {{ $t('AUTONOMIA_GUIDE.ACTION.CANCELLED') }}
                </p>
                <p
                  v-else-if="item.acaoResultado"
                  class="mb-0 text-sm font-medium break-words"
                  :class="
                    item.acaoEstado === 'feita'
                      ? 'text-n-teal-11'
                      : 'text-n-ruby-11'
                  "
                >
                  {{ item.acaoResultado }}
                </p>
                <div
                  v-if="mostraBotoes(item.acaoEstado)"
                  class="flex flex-wrap gap-2"
                >
                  <Button
                    :label="$t('AUTONOMIA_GUIDE.ACTION.CONFIRM')"
                    :disabled="item.acaoEstado === 'executando'"
                    class="min-h-11"
                    blue
                    @click="confirmarAcao(item)"
                  />
                  <Button
                    v-if="item.acaoEstado !== 'cancelada'"
                    :label="$t('AUTONOMIA_GUIDE.ACTION.CANCEL')"
                    :disabled="item.acaoEstado === 'executando'"
                    class="min-h-11"
                    slate
                    faded
                    @click="store.marcarAcao(item.id, 'cancelada')"
                  />
                </div>
              </div>

              <!-- Uma pergunta com várias partes ganha um botão por tela e um link por artigo
                   (#636). Com no máximo uma tela e um artigo, fica exatamente como antes — um
                   botão de cada, rótulo curto e fixo, que não estoura a largura do painel. Com
                   mais de um item numa lista, os botões de tela ficam soltos (o texto de cada um
                   já diz "Ir para", repetir isso num título de seção seria redundante — revisão
                   #637); só os links de artigo ganham título, porque "Ler: {título}" sozinho não
                   deixa óbvio que a lista inteira é "para ler depois". -->
              <div v-if="layoutMultiplo(item)" class="flex flex-col gap-3">
                <div
                  v-if="telasValidas(item).length"
                  class="flex flex-wrap gap-2"
                >
                  <Button
                    v-for="(entrada, indice) in telasValidas(item)"
                    :key="chaveDaTela(entrada.nav)"
                    :label="
                      entrada.nav.rotulo
                        ? $t('AUTONOMIA_GUIDE.GO_TO_SCREEN_NAMED', {
                            rotulo: entrada.nav.rotulo,
                          })
                        : $t('AUTONOMIA_GUIDE.GO_TO_SCREEN_NUMBERED', {
                            numero: indice + 1,
                          })
                    "
                    icon="i-lucide-arrow-right"
                    trailing-icon
                    blue
                    faded
                    class="max-w-full min-h-11 [&>span]:truncate"
                    @click="navigateTo(entrada.nav)"
                  />
                </div>
                <div
                  v-if="(item.artigos || []).length"
                  class="flex flex-col gap-1"
                >
                  <p class="mb-0 text-xs font-medium text-n-slate-11">
                    {{ $t('AUTONOMIA_GUIDE.READ_SECTION') }}
                  </p>
                  <Button
                    v-for="artigoItem in item.artigos"
                    :key="artigoItem.ref"
                    :label="
                      $t('AUTONOMIA_GUIDE.READ_ARTICLE_NAMED', {
                        titulo: artigoItem.titulo,
                      })
                    "
                    link
                    teal
                    justify="start"
                    class="max-w-full min-h-11 [&>span]:truncate"
                    @click="abrirArtigo(artigoItem)"
                  />
                </div>
              </div>
              <div
                v-else-if="
                  telasValidas(item).length || (item.artigos || []).length
                "
                class="flex flex-wrap gap-2"
              >
                <!-- O rótulo vinha do título do fluxo, escrito para o manual
                     e longo demais para um painel estreito: ele estourava a
                     largura e levava a seta junto, deixando o botão com cara
                     de texto solto. Agora é frase curta e fixa, e o que
                     sobrar é cortado. -->
                <Button
                  v-if="telasValidas(item).length"
                  :label="$t('AUTONOMIA_GUIDE.GO_TO_SCREEN')"
                  icon="i-lucide-arrow-right"
                  trailing-icon
                  blue
                  faded
                  class="max-w-full min-h-11 [&>span]:truncate"
                  @click="navigateTo(telasValidas(item)[0].nav)"
                />
                <!-- Botão secundário, separado do de navegação: ele não leva
                     a lugar nenhum da conta, abre o artigo que a ferramenta
                     leu (#617). -->
                <Button
                  v-if="(item.artigos || []).length"
                  :label="$t('AUTONOMIA_GUIDE.READ_ARTICLE')"
                  icon="i-lucide-book-open"
                  trailing-icon
                  slate
                  faded
                  class="max-w-full min-h-11 [&>span]:truncate"
                  @click="abrirArtigo(item.artigos[0])"
                />
              </div>
            </div>
          </template>
          <CopilotLoader
            v-if="ocupado && !transcrevendo"
            :label="$t('AUTONOMIA_GUIDE.THINKING')"
          />
        </div>
        <div
          v-else-if="!abrindoConversa"
          class="flex-1 flex flex-col gap-3 px-1 py-2"
        >
          <h3 class="text-base font-medium text-n-slate-12 leading-7">
            {{ $t('AUTONOMIA_GUIDE.TITLE') }}
          </h3>
          <p class="text-sm text-n-slate-11 leading-6">
            {{ introducao || $t('AUTONOMIA_GUIDE.KICK_OFF') }}
          </p>
          <div class="flex flex-col gap-2 mt-2">
            <p
              v-if="sugestoesDaTela.length"
              class="mb-0 text-xs font-medium text-n-slate-11"
            >
              {{ $t('AUTONOMIA_GUIDE.SUGGESTIONS_THIS_SCREEN') }}
            </p>
            <button
              v-for="(suggestion, i) in suggestions"
              :key="i"
              data-sugestao
              :disabled="ocupado || gravandoVoz"
              class="text-left text-sm text-n-slate-12 bg-n-alpha-1 hover:bg-n-alpha-2 rounded-lg px-3 py-2 min-h-11 transition-colors disabled:cursor-not-allowed disabled:opacity-60"
              @click="sendMessage(suggestion.pergunta)"
            >
              {{ suggestion.rotulo }}
            </button>
          </div>
        </div>
      </div>

      <div class="mx-3 mt-px mb-2">
        <GuideEtiquetaTela
          :tela="telaAtual"
          :oculta="semTelaNaProxima"
          @remover="semTelaNaProxima = true"
        />
        <!-- Uma conta, um composer: trocar de conta descarta a gravação e o áudio que
             esperava a vez, que senão sairia na conta nova. -->
        <GuideComposer
          :key="accountId"
          class="mb-1 w-full"
          :is-busy="ocupado"
          :arquivos="pendentes"
          :on-enviar-voz="enviarVoz"
          :vagas="vagas"
          @send="sendMessage"
          @sem-microfone="useAlert($t('AUTONOMIA_GUIDE.VOICE.NO_MIC'))"
          @gravacao-falhou="useAlert($t('AUTONOMIA_GUIDE.VOICE.RECORD_FAILED'))"
          @anexar="anexarArquivo"
          @gravando="gravandoVoz = $event"
          @limite-de-anexos="avisarLimiteDeAnexos"
          @remover="store.removeArquivo"
        />
      </div>
    </div>
  </div>
  <template v-else />
</template>
