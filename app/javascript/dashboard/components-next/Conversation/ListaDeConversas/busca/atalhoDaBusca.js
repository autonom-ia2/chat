import { ref } from 'vue';
import { useEventListener } from '@vueuse/core';
import { useRouter } from 'vue-router';
import { useMapGetter } from 'dashboard/composables/store';
import { useListaNova } from '../useListaNova';

// #2211 — ⌘/Ctrl+K foca o campo "Buscar conversa" da lista. De outra tela, abre Conversas com o
// campo focado. Com a chave lista_quem_espera; sem ela, ⌘K segue abrindo a barra de comandos.
// O pedido de foco fica guardado até o campo existir na tela.
export const pedidoDeFoco = ref(0);
export const pedirFoco = () => {
  pedidoDeFoco.value += 1;
};
// O último pedido que um campo já atendeu: o campo que monta depois do pedido (vindo de outra
// tela) foca uma vez, e o que monta sem pedido não rouba o foco.
export const focoAtendido = ref(0);

const CAMPO = '[data-campo-da-busca]';

export function useAtalhoDaBusca() {
  const listaNova = useListaNova();
  const router = useRouter();
  const contaId = useMapGetter('getCurrentAccountId');

  // Na fase de captura, antes da barra de comandos (que escuta no documento) e do editor.
  useEventListener(
    window,
    'keydown',
    evento => {
      if (!listaNova.value) return;
      if (!(evento.metaKey || evento.ctrlKey) || evento.code !== 'KeyK') return;
      if (evento.altKey || evento.shiftKey) return;
      evento.preventDefault();
      evento.stopImmediatePropagation();
      pedirFoco();
      if (!document.querySelector(CAMPO)) {
        router.push({ name: 'home', params: { accountId: contaId.value } });
      }
    },
    { capture: true }
  );
}
