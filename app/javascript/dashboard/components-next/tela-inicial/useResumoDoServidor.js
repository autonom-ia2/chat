import { onBeforeUnmount, onMounted, ref } from 'vue';
import { useDebounceFn } from '@vueuse/core';
import { useEmitter } from 'dashboard/composables/emitter';
import { buscarResumo, lerResumo } from './resumoDoServidor';

// O painel avisa 'fetch_conversation_stats' quando chega mensagem ou a conversa muda de status
// ou de responsável (actionCable). A tela junta os avisos de uma rajada numa consulta só.
export const EVENTO_CONVERSAS_MUDARAM = 'fetch_conversation_stats';
const ESPERA_DA_RAJADA = 1500;
// Conta movimentada: avisos seguidos não seguram a atualização mais que isso.
const ESPERA_MAXIMA = 10000;

// #1801 — carrega ao abrir (a tela volta a montar sempre que a pessoa sai de uma conversa)
// e quando as conversas mudam. Sem consulta periódica.
export const useResumoDoServidor = () => {
  const resumo = ref(lerResumo({}));
  const estado = ref('carregando');
  let pedido = 0;
  let ativo = true;

  const atualizar = async () => {
    if (!ativo) return;
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
    useDebounceFn(atualizar, ESPERA_DA_RAJADA, { maxWait: ESPERA_MAXIMA })
  );
  onMounted(atualizar);
  // Um aviso pouco antes de sair dispararia a consulta com a tela já fora.
  onBeforeUnmount(() => {
    ativo = false;
  });

  return { resumo, estado, atualizar };
};
