import { onMounted, ref } from 'vue';
import { useDebounceFn } from '@vueuse/core';
import { useEmitter } from 'dashboard/composables/emitter';
import { buscarFila } from './filaDoServidor';

// O painel avisa 'fetch_conversation_stats' quando chega mensagem, a conversa muda de status
// ou de responsável. A tela junta os avisos de uma rajada numa consulta só.
export const EVENTO_CONVERSAS_MUDARAM = 'fetch_conversation_stats';
const ESPERA_DA_RAJADA = 1500;

// #1801 — a fila exata do servidor para a tela inicial: carrega ao abrir (a tela volta a
// montar sempre que a pessoa sai de uma conversa) e quando as conversas mudam.
export const useFilaDoServidor = () => {
  const fila = ref({ esperamVoce: 0, esperamAlguem: 0, proxima: null });
  const estado = ref('carregando');
  let pedido = 0;

  const atualizar = async () => {
    pedido += 1;
    const este = pedido;
    try {
      const resposta = await buscarFila();
      if (este !== pedido) return;
      fila.value = resposta;
      estado.value = 'pronto';
    } catch {
      // Falhou: fica o último número bom; sem nenhum, a tela mostra o erro.
      if (este === pedido && estado.value !== 'pronto') estado.value = 'erro';
    }
  };

  useEmitter(
    EVENTO_CONVERSAS_MUDARAM,
    useDebounceFn(atualizar, ESPERA_DA_RAJADA)
  );
  onMounted(atualizar);

  return { fila, estado, atualizar };
};
