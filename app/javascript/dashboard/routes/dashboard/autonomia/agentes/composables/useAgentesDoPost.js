import { computed, ref, toValue, watch } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import AgentesDoPostAPI from 'dashboard/api/agentesDoPost';

// Os comentários do post em Agentes (#2469, PR 3a do #2436). A lista vem só do banco (useAgentesDoPost); cada cartão e
// a página leem o detalhe, na Meta na hora (useAgenteDoPost). Tudo atrás da flag do cuidado (meta_ads_comentarios_ia,
// "Sem chave nova"): sem ela, nada é lido.

export const ICONE_DA_REDE = {
  instagram: 'i-woot-instagram-color',
  facebook: 'i-ri-facebook-circle-fill text-n-blue-9',
};
// O anúncio nas duas redes mostra os dois ícones.
export const redesDoCuidado = network =>
  network === 'both' ? ['instagram', 'facebook'] : [network];

// O estado na tela: o cuidado ligado está "Cuidando"; o pausado, "Pausado" (conta como parado no cabeçalho).
export const estadoDoCuidado = status =>
  status === 'on' ? 'cuidando' : 'pausado';

// O título do cartão: a primeira frase da legenda, se for curta; senão o começo, cortado num espaço. Só é fim de frase
// o sinal seguido de espaço ou no fim do texto: "R$ 39.90" não corta.
const TITULO_MAX = 48;
const FINS = ['?', '!', '.'];
const fimDeFrase = (texto, indice) =>
  FINS.includes(texto[indice]) &&
  (indice + 1 === texto.length || texto[indice + 1] === ' ');
export const tituloDaLegenda = (legenda = '') => {
  const texto = (legenda || '').trim();
  const limite = Math.min(texto.length, TITULO_MAX);
  let fim = -1;
  for (let indice = 1; indice < limite && fim < 0; indice += 1) {
    if (fimDeFrase(texto, indice)) fim = indice;
  }
  if (fim > 0) {
    const corte = fim + 1;
    return { titulo: texto.slice(0, corte), resto: texto.slice(corte).trim() };
  }
  if (texto.length <= TITULO_MAX) return { titulo: texto, resto: '' };
  const espaco = texto.lastIndexOf(' ', TITULO_MAX);
  const corte = espaco > 0 ? espaco : TITULO_MAX;
  return { titulo: `${texto.slice(0, corte)}…`, resto: texto };
};

// As portas que escrevem, sem repetir o agente: o anúncio com o mesmo agente nas duas redes mostra um nome só.
export const agentesDasPortas = (portas = []) => {
  const vistos = new Set();
  return portas
    .map(porta => porta.agente)
    .filter(agente => {
      if (!agente || vistos.has(agente.id)) return false;
      vistos.add(agente.id);
      return true;
    });
};

// #2487 — o motivo de verdade de cada porta que não escreve (o mesmo do recuo da Escrita), com a rede e o nome da
// caixa: "No Instagram, a caixa X não tem agente atendendo.". Vazio quando todas escrevem. O motivo da conta inteira
// (sem a chave, agentes desligados) sai uma vez só, mesmo no anúncio nas duas redes.
export const motivosDasPortas = (portas, t) => [
  ...new Set(
    (portas || [])
      .filter(porta => porta.motivo)
      .map(porta =>
        t(`AGENTS.AGENTE_DO_POST.MOTIVO_DA_PORTA.${porta.motivo}`, {
          rede: t(`AGENTS.AGENTE_DO_POST.REDE.${porta.network.toUpperCase()}`),
          caixa: porta.caixa || '',
        })
      )
  ),
];

const useFlags = (...flags) => {
  const ligada = useMapGetter('accounts/isFeatureEnabledonAccount');
  const conta = useMapGetter('getCurrentAccountId');
  return computed(() =>
    flags.every(flag => ligada.value?.(conta.value, flag) === true)
  );
};

export function useAgentesDoPost() {
  const ligada = useFlags(FEATURE_FLAGS.META_ADS_COMENTARIOS_IA);
  // "Qual post?" lê os posts do Seus posts: sem as flags dele, a criação pelo post não aparece.
  const comPosts = useFlags(
    FEATURE_FLAGS.META_ADS_COMENTARIOS_IA,
    FEATURE_FLAGS.SEUS_POSTS,
    FEATURE_FLAGS.SEUS_POSTS_COMENTARIOS
  );
  const cuidados = ref([]);
  const carregado = ref(false);

  // Falha (rede, 403, 404 sem a flag): a lista de Agentes segue sem os cartões dos posts.
  const carregar = async () => {
    if (!ligada.value) {
      cuidados.value = [];
      carregado.value = true;
      return;
    }
    try {
      const { data } = await AgentesDoPostAPI.list();
      cuidados.value = data.cuidados || [];
    } catch {
      cuidados.value = [];
    } finally {
      carregado.value = true;
    }
  };

  const cuidando = computed(
    () => cuidados.value.filter(cuidado => cuidado.status === 'on').length
  );
  const pausados = computed(() => cuidados.value.length - cuidando.value);

  // As flags da conta podem chegar depois da tela: a lista é lida de novo quando a flag liga.
  watch(ligada, (agora, antes) => {
    if (agora && !antes) carregar();
  });

  return {
    ligada,
    comPosts,
    cuidados,
    carregado,
    carregar,
    cuidando,
    pausados,
  };
}

// Cada detalhe lê a Meta (comentários, legenda, capa): os cartões da lista leem no máximo 3 de cada vez, para uma conta
// com muitos posts cuidados não gastar de uma vez o limite da Meta, que o motor dos comentários usa na mesma conexão.
const EM_PARALELO = 3;
let correndo = 0;
const fila = [];
const proxima = () => {
  if (correndo >= EM_PARALELO || !fila.length) return;
  const { tarefa, resolve, reject } = fila.shift();
  correndo += 1;
  tarefa()
    .then(resolve, reject)
    .finally(() => {
      correndo -= 1;
      proxima();
    });
};
const naFila = tarefa =>
  new Promise((resolve, reject) => {
    fila.push({ tarefa, resolve, reject });
    proxima();
  });

// O detalhe de um cuidado: o cartão (só lê) e a página (lê, pausa, volta e testa). `id`: valor, ref ou getter; vazio,
// não lê. `emFila`: o cartão lê pela fila (EM_PARALELO); a página lê na hora.
export function useAgenteDoPost(id, { emFila = false } = {}) {
  const detalhe = ref(null);
  const carregando = ref(false);
  // 'acesso' (403), 'sumiu' (404) ou 'rede'; o código do servidor fica em `motivo` (not_inbox_member, no_post...).
  const erro = ref(null);
  const motivo = ref(null);
  const mudando = ref(false);

  const ERRO = { 403: 'acesso', 404: 'sumiu' };
  let leitura = 0;
  const carregar = async () => {
    const atual = toValue(id);
    if (!atual) return;
    leitura += 1;
    const minha = leitura;
    carregando.value = true;
    erro.value = null;
    motivo.value = null;
    try {
      const ler = () => AgentesDoPostAPI.get(atual);
      const { data } = await (emFila ? naFila(ler) : ler());
      if (minha === leitura) detalhe.value = data;
    } catch (error) {
      if (minha !== leitura) return;
      erro.value = ERRO[error?.response?.status] || 'rede';
      motivo.value = error?.response?.data?.error || null;
    } finally {
      if (minha === leitura) carregando.value = false;
    }
  };

  // Pausar e voltar a cuidar: true quando valeu.
  const mudarEstado = async status => {
    mudando.value = true;
    try {
      const { data } = await AgentesDoPostAPI.estado(toValue(id), status);
      detalhe.value = data;
      return true;
    } catch {
      return false;
    } finally {
      mudando.value = false;
    }
  };

  // O Testar: a resposta do servidor, ou { status: 'erro', codigo } com o código do erro (ai_unavailable,
  // no_credential, …), ou { status: 'erro' }.
  const testar = async ({ pergunta, network }) => {
    try {
      const { data } = await AgentesDoPostAPI.testar(toValue(id), {
        pergunta,
        network,
      });
      return data;
    } catch (error) {
      return { status: 'erro', codigo: error?.response?.data?.error || null };
    }
  };

  watch(() => toValue(id), carregar, { immediate: true });

  return {
    detalhe,
    carregando,
    erro,
    motivo,
    mudando,
    carregar,
    mudarEstado,
    testar,
  };
}
