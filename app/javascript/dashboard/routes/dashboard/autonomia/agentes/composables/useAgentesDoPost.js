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

// O título do cartão: a primeira frase da legenda, se for curta; senão o começo, cortado num espaço.
const TITULO_MAX = 48;
const FINS = ['?', '!', '.'];
export const tituloDaLegenda = (legenda = '') => {
  const texto = (legenda || '').trim();
  const fins = FINS.map(fim => texto.indexOf(fim)).filter(
    indice => indice > 0 && indice < TITULO_MAX
  );
  if (fins.length) {
    const corte = Math.min(...fins) + 1;
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

const useFlagDoCuidado = () => {
  const ligada = useMapGetter('accounts/isFeatureEnabledonAccount');
  const conta = useMapGetter('getCurrentAccountId');
  return computed(
    () =>
      ligada.value?.(conta.value, FEATURE_FLAGS.META_ADS_COMENTARIOS_IA) ===
      true
  );
};

export function useAgentesDoPost() {
  const ligada = useFlagDoCuidado();
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

  return { ligada, cuidados, carregado, carregar, cuidando, pausados };
}

// O detalhe de um cuidado: o cartão (só lê) e a página (lê, pausa, volta e testa). `id`: valor, ref ou getter.
export function useAgenteDoPost(id) {
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
      const { data } = await AgentesDoPostAPI.get(atual);
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

  // O Testar: a resposta do servidor, ou { status: 'erro', ia: true } com a IA fora do ar, ou { status: 'erro' }.
  const testar = async ({ pergunta, formato, network }) => {
    try {
      const { data } = await AgentesDoPostAPI.testar(toValue(id), {
        pergunta,
        formato,
        network,
      });
      return data;
    } catch (error) {
      return {
        status: 'erro',
        ia: error?.response?.data?.error === 'ai_unavailable',
      };
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
