// Estado da conexão do WhatsApp de uma caixa WAHA comum, para a faixa da lista
// (#1941, item 5). Consulta ao abrir e a cada 60 s enquanto a lista está montada;
// troca de caixa ou saída da lista param a consulta. Sem resposta, sem faixa.
import { computed, onBeforeUnmount, ref, toValue, watch } from 'vue';
import WahaInboxAPI from 'dashboard/api/wahaInbox';
import { INBOX_TYPES } from 'dashboard/helper/inbox';

export const INTERVALO_DA_CONSULTA = 60 * 1000;

// Só estes pedem ação de quem atende. "connecting" e "unknown" passam sozinhos.
export const ESTADOS_COM_FAIXA = ['awaiting_scan', 'failed', 'disconnected'];

// Sem acesso à caixa (ou caixa que não é do conector): a resposta não muda
// consultando de novo, então a consulta para.
const RECUSAS_DEFINITIVAS = [401, 403, 404, 422];

const idDaCaixaDoWaha = caixa =>
  caixa?.id && caixa.channel_type === INBOX_TYPES.API && caixa.waha_provider
    ? caixa.id
    : null;

export const useEstadoDaConexao = caixa => {
  const estado = ref(null);
  let relogio = null;
  // Cada consulta leva o número da rodada: resposta de caixa antiga não pinta a faixa da nova.
  let rodada = 0;

  const parar = () => {
    clearInterval(relogio);
    relogio = null;
    rodada += 1;
    estado.value = null;
  };

  const consultar = async (id, daRodada) => {
    try {
      const { data } = await WahaInboxAPI.status(id);
      if (daRodada === rodada) estado.value = data?.status ?? null;
    } catch (erro) {
      if (daRodada !== rodada) return;
      // Erro de rede ou do servidor: sem faixa até a próxima consulta.
      estado.value = null;
      if (RECUSAS_DEFINITIVAS.includes(erro?.response?.status)) parar();
    }
  };

  watch(
    () => idDaCaixaDoWaha(toValue(caixa)),
    id => {
      parar();
      if (!id) return;
      const daRodada = rodada;
      consultar(id, daRodada);
      relogio = setInterval(
        () => consultar(id, daRodada),
        INTERVALO_DA_CONSULTA
      );
    },
    { immediate: true }
  );

  onBeforeUnmount(parar);

  return {
    estado,
    mostrar: computed(() => ESTADOS_COM_FAIXA.includes(estado.value)),
  };
};
