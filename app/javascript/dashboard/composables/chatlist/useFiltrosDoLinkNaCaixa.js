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
// `no_funil=1` (#1999): só as de cliente num funil que a pessoa vê no Números. Vem junto de um dos outros dois.
const PARAMETROS = ['da_ia', 'esperando_min', 'no_funil'];

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
  noFunil: destino?.query?.no_funil === '1',
});

// O filtro que a lista pede ao servidor. No Spam e na Lixeira a pasta manda; com filtro avançado ou pasta salva, a lista
// vem de outro pedido e o link não vale. Sempre as duas chaves: o merge dos filtros da store (UPDATE_CHAT_LIST_FILTERS)
// não deixa valor antigo para trás.
export const filtroDoLinkDaLista = ({
  daIa,
  esperandoMin,
  noFunil,
  pasta,
  filtroAvancado,
}) => {
  if (pasta || filtroAvancado) {
    return { daIa: undefined, esperandoMin: undefined, noFunil: undefined };
  }
  const ligado = Boolean(daIa || esperandoMin);
  return {
    daIa: daIa || undefined,
    esperandoMin: esperandoMin ?? undefined,
    noFunil: (ligado && noFunil) || undefined,
  };
};

// A lista com o filtro do link de quem não tem a aba "Todas" (#1999, ex.: função com conversation_unassigned_manage): o
// número conta tudo o que a pessoa vê, então a lista pede "todas" e o servidor (ConversationFinder, com as permissões de
// quem pede) corta o que ela não pode ver: as Minhas mais as Não atribuídas, o mesmo das abas dela somadas. Com "Todas"
// ou sem o filtro, vale a aba escolhida.
export const abaDaListaComLink = ({ daIa, esperandoMin }, abas, aba, todas) =>
  (daIa || esperandoMin) && !abas.includes(todas) ? todas : aba;

// Onde a página da lista fica gravada (#1999): a resposta grava na aba que a lista pediu (a da lista, não a escolhida),
// e a próxima página e o fim da lista têm que ser lidos no mesmo lugar. Com o filtro avançado, a gaveta dele.
export const chaveDaPaginaDaLista = (filtroAvancado, abaDaLista) =>
  filtroAvancado ? 'appliedFilters' : abaDaLista;

// O funil da lista com o filtro do link (#1999): o escopo vem do link, e o funil escolhido na caixa fica de lado (sem
// gravar nada: a escolha salva volta quando o link sai). Sem o filtro, o funil escolhido.
export const funilDoFiltroDoLink = ({ daIa, esperandoMin }, funil, todos) =>
  daIa || esperandoMin ? todos : funil;

// A aba em que a caixa abre com o filtro do link (#1999): o Números conta todas as conversas que a pessoa enxerga, então
// a caixa abre em "Todas", quando a pessoa tem essa aba, para o número da lista bater com o do Números. Sem o filtro do
// link (ou sem "Todas"), null: vale a aba de sempre.
export const abaDoFiltroDoLink = ({ daIa, esperandoMin }, abas, todas) =>
  (daIa || esperandoMin) && abas.includes(todas) ? todas : null;

// O status com o filtro do link (#1999): o Números conta as conversas abertas, então a caixa abre em "Abertas" mesmo
// que a pessoa tenha salvo outro status. Só nesta abertura: a escolha salva da pessoa não muda. Sem o filtro, o de sempre.
export const statusDoFiltroDoLink = ({ daIa, esperandoMin }, status, aberto) =>
  daIa || esperandoMin ? aberto : status;

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
      : { daIa: false, esperandoMin: null, noFunil: false }
  );
  const daIa = computed(() => filtros.value.daIa);
  const esperandoMin = computed(() => filtros.value.esperandoMin);
  const noFunil = computed(() => filtros.value.noFunil);
  // Muda quando qualquer valor do link muda (#1999): a lista relê, e a releitura periódica usa os valores novos.
  const assinatura = computed(() =>
    [daIa.value, esperandoMin.value, noFunil.value].join('|')
  );
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

  // O link do filtro ligado, só com valores que a caixa oferece.
  const linkDoFiltro = computed(() => ({
    ...(daIa.value ? { da_ia: '1' } : {}),
    ...(esperandoMin.value
      ? { esperando_min: String(esperandoMin.value) }
      : {}),
    ...(noFunil.value && (daIa.value || esperandoMin.value)
      ? { no_funil: '1' }
      : {}),
  }));

  // Voltar da conversa para a lista (marcar como não lida, excluir): com o filtro ligado, a lista volta filtrada.
  const irParaALista = (path, filtroLigado) =>
    router.push({ path, query: filtroLigado ? linkDoFiltro.value : {} });

  // Endereço da conversa para abrir em outra aba (Ctrl/Cmd+clique): leva o link, como o clique normal.
  const enderecoComLink = path =>
    router.resolve({ path, query: linkDoFiltro.value }).fullPath;

  return {
    daIa,
    esperandoMin,
    noFunil,
    assinatura,
    limpar,
    limparTudo,
    linkDoFiltro,
    irParaALista,
    enderecoComLink,
  };
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
