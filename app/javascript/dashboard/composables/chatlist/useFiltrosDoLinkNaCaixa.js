// Filtros pelo link na caixa de conversas (Números F2, #1883). Os botões do Números abrem a lista já filtrada:
// `?da_ia=1` = recebidas da IA; `?esperando_min=30` = esperando alguém há mais de 30 min. O servidor confere de novo
// (Crm::ConversationFinderComFiltrosDoLink); aqui, valor que a caixa não oferece é ignorado.
// O filtro é o que está no endereço, e só nele: abrir uma conversa da lista filtrada leva o link junto (a lista ao lado
// segue filtrada); qualquer outro caminho (o menu, o card do CRM, Contatos) chega sem o link e mostra a lista inteira.
import { computed, onBeforeUnmount, watch } from 'vue';
import { useRoute, useRouter } from 'vue-router';

const ESPERANDO_MIN = { MIN: 1, MAX: 1440 };
const SO_DIGITOS = valor =>
  valor !== '' && [...valor].every(c => c >= '0' && c <= '9');
// "Esperando há mais de N min": a conversa que cruza o limite entra na próxima releitura, uma por minuto.
export const RELEITURA_PERIODICA_MS = 60000;

// As listas comuns da caixa (as que leem GET conversations). Pastas salvas usam o filtro avançado e ficam de fora.
const LISTAS = [
  'home',
  'inbox_dashboard',
  'label_conversations',
  'team_conversations',
  'conversation_mentions',
  'conversation_unattended',
  'conversation_participating',
];
// A conversa aberta ao lado de cada lista.
const CONVERSAS = [
  'inbox_conversation',
  'conversation_through_inbox',
  'conversations_through_label',
  'conversations_through_team',
  'conversation_through_mentions',
  'conversation_through_unattended',
  'conversation_through_participating',
];
const PARAMETROS = ['da_ia', 'esperando_min'];

const minutosValidos = valor => {
  const texto = String(valor ?? '');
  if (!SO_DIGITOS(texto)) return null;
  const minutos = Number(texto);
  return minutos >= ESPERANDO_MIN.MIN && minutos <= ESPERANDO_MIN.MAX
    ? minutos
    : null;
};

export const filtrosDoEndereco = destino => ({
  daIa: destino?.query?.da_ia === '1',
  esperandoMin: minutosValidos(destino?.query?.esperando_min),
});

export const naCaixa = destino =>
  LISTAS.includes(destino?.name) || CONVERSAS.includes(destino?.name);

const doLink = destino =>
  Object.fromEntries(
    PARAMETROS.filter(chave => destino?.query?.[chave] !== undefined).map(
      chave => [chave, destino.query[chave]]
    )
  );

// O "Limpar" troca o endereço por um sem o link; a guarda deixa passar esse destino exato, uma vez, sem devolver o link.
let destinoDoLimpar = null;

// Guarda do roteador: da lista filtrada (ou da conversa aberta nela) para uma conversa, o link vai junto.
export const levarLinkParaConversa = (destino, origem) => {
  if (destinoDoLimpar && destino.fullPath === destinoDoLimpar) {
    destinoDoLimpar = null;
    return true;
  }
  if (!CONVERSAS.includes(destino.name) || !naCaixa(origem)) return true;
  const link = doLink(origem);
  if (!Object.keys(link).length || Object.keys(doLink(destino)).length) {
    return true;
  }
  return {
    path: destino.path,
    query: { ...destino.query, ...link },
    hash: destino.hash,
  };
};

const guardasInstaladas = new WeakSet();

export const useFiltrosDoLinkNaCaixa = () => {
  const route = useRoute();
  const router = useRouter();

  if (!guardasInstaladas.has(router)) {
    guardasInstaladas.add(router);
    router.beforeEach(levarLinkParaConversa);
  }

  const filtros = computed(() =>
    naCaixa(route)
      ? filtrosDoEndereco(route)
      : { daIa: false, esperandoMin: null }
  );
  const daIa = computed(() => filtros.value.daIa);
  const esperandoMin = computed(() => filtros.value.esperandoMin);
  const linkNoEndereco = computed(() => Object.keys(doLink(route)).length > 0);

  // Tira só o link do endereço; o filtro desliga junto, porque ele é o endereço.
  const limpar = async () => {
    if (!linkNoEndereco.value) return;
    const query = { ...route.query };
    PARAMETROS.forEach(chave => delete query[chave]);
    const destino = router.resolve({
      name: route.name,
      params: route.params,
      query,
      hash: route.hash,
    });
    destinoDoLimpar = destino.fullPath;
    try {
      await router.replace(destino);
    } finally {
      destinoDoLimpar = null;
    }
  };

  // A seta "Limpar filtros": um clique tira tudo. Com o filtro do link ligado, tirar o link já relê a lista (e a releitura
  // tira o filtro avançado); com o link no endereço mas sem valor que a caixa ofereça (`?da_ia=0`), tira e relê.
  const limparTudo = async reler => {
    const filtroLigado = Boolean(daIa.value || esperandoMin.value);
    if (linkNoEndereco.value) await limpar();
    if (!filtroLigado) reler();
  };

  return { daIa, esperandoMin, limpar, limparTudo };
};

// Com "esperando" ligado: relê a lista uma vez por minuto com a aba do navegador visível, e logo que ela volta a ficar
// visível.
export const useReleituraPeriodica = (ligado, reler) => {
  let relogio = null;
  const aoVoltarAVer = () => {
    if (ligado.value && document.visibilityState === 'visible') reler();
  };
  const parar = () => {
    clearInterval(relogio);
    relogio = null;
  };
  watch(
    ligado,
    valor => {
      parar();
      if (!valor) return;
      relogio = setInterval(() => {
        if (document.visibilityState === 'visible') reler();
      }, RELEITURA_PERIODICA_MS);
    },
    { immediate: true }
  );
  document.addEventListener('visibilitychange', aoVoltarAVer);
  onBeforeUnmount(() => {
    parar();
    document.removeEventListener('visibilitychange', aoVoltarAVer);
  });
};
