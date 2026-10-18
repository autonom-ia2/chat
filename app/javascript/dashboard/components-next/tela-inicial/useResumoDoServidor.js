import { onMounted, ref } from 'vue';
import { useDebounceFn } from '@vueuse/core';
import { useEmitter } from 'dashboard/composables/emitter';
import { buscarResumo, lerResumo } from './resumoDoServidor';

// O painel avisa 'fetch_conversation_stats' quando chega mensagem ou a conversa muda de status
// ou de responsável (actionCable). A tela junta os avisos de uma rajada numa consulta só.
export const EVENTO_CONVERSAS_MUDARAM = 'fetch_conversation_stats';
const ESPERA_DA_RAJADA = 1500;

// #1801 — carrega ao abrir (a tela volta a montar sempre que a pessoa sai de uma conversa)
// e quando as conversas mudam. Sem consulta periódica.
export const useResumoDoServidor = () => {
  const resumo = ref(lerResumo({}));
  const estado = ref('carregando');
  let pedido = 0;

  const atualizar = async () => {
    pedido += 1;
    const este = pedido;
    try {
      const novo = await buscarResumo();
      if (este !== pedido) return;
      resumo.value = novo;
      estado.value = 'pronto';
    } catch {
      // Falhou: fica o último resumo bom; sem nenhum, a tela mostra o erro.
      if (este === pedido && estado.value !== 'pronto') estado.value = 'erro';
    }
  };

  useEmitter(
    EVENTO_CONVERSAS_MUDARAM,
    useDebounceFn(atualizar, ESPERA_DA_RAJADA)
  );
  onMounted(atualizar);

  return { resumo, estado, atualizar };
};
