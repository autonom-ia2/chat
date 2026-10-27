import { ref } from 'vue';
import { useEventListener } from '@vueuse/core';
import { useRoute } from 'vue-router';
import { useListaNova } from '../useListaNova';

// #2211 — ⌘/Ctrl+K foca o campo "Buscar" da lista, só na tela de Conversas (a lista e a conversa
// aberta) e com a chave lista_quem_espera (decisão do Rodrigo). Fora de Conversas, ou sem a chave,
// o ⌘K segue abrindo a barra de comandos, como antes; o atalho não navega para lugar nenhum.
export const pedidoDeFoco = ref(0);
export const pedirFoco = () => {
  pedidoDeFoco.value += 1;
};
// O último pedido que um campo já atendeu: o campo que monta depois do pedido foca uma vez, e o
// que monta sem pedido não rouba o foco.
export const focoAtendido = ref(0);

// As rotas que mostram a lista de conversas (ConversationView, em conversation.routes.js).
export const ROTAS_DE_CONVERSAS = [
  'home',
  'inbox_conversation',
  'inbox_dashboard',
  'conversation_through_inbox',
  'label_conversations',
  'conversations_through_label',
  'team_conversations',
  'conversations_through_team',
  'folder_conversations',
  'conversations_through_folders',
  'conversation_mentions',
  'conversation_through_mentions',
  'conversation_unattended',
  'conversation_through_unattended',
  'conversation_participating',
  'conversation_through_participating',
];

const CAMPO = '[data-campo-da-busca]';

// A barra de comandos (ninja-keys) já está aberta: o ⌘K é dela, e o foco não vai para a busca atrás.
const barraDeComandosAberta = () =>
  Boolean(document.querySelector('ninja-keys')?.visible);

// O campo está na tela e visível (com filtro avançado, pasta salva ou a conversa aberta no celular,
// ele não aparece).
const campoVisivel = () => {
  const campo = document.querySelector(CAMPO);
  return Boolean(campo && campo.getClientRects().length);
};

export function useAtalhoDaBusca() {
  const listaNova = useListaNova();
  const route = useRoute();

  // Na fase de captura, antes da barra de comandos (que escuta no documento) e do editor.
  useEventListener(
    window,
    'keydown',
    evento => {
      if (!listaNova.value) return;
      if (!(evento.metaKey || evento.ctrlKey) || evento.code !== 'KeyK') return;
      if (evento.altKey || evento.shiftKey) return;
      if (!ROTAS_DE_CONVERSAS.includes(route?.name)) return;
      if (barraDeComandosAberta() || !campoVisivel()) {
        // Barra de comandos já aberta, ou campo escondido (filtro avançado, pasta salva, conversa
        // aberta no celular): o ⌘K fica com a barra, e nenhum pedido fica pendente para roubar o foco.
        focoAtendido.value = pedidoDeFoco.value;
        return;
      }
      evento.preventDefault();
      evento.stopImmediatePropagation();
      pedirFoco();
    },
    { capture: true }
  );
}
