import { computed } from 'vue';
import { useRoute } from 'vue-router';
import { pedidoDeConversaVazia } from 'dashboard/components-next/Conversation/ListaDeConversas/busca/caixasDaConversaVazia';
import { useListaNova } from 'dashboard/components-next/Conversation/ListaDeConversas/useListaNova';

const CONVERSATION_ROUTES = [
  'inbox_conversation',
  'conversation_through_inbox',
  'conversations_through_label',
  'team_conversations_through_label',
  'conversations_through_folders',
  'conversation_through_mentions',
  'conversation_through_unattended',
  'conversation_through_participating',
  'inbox_view_conversation',
];

// Tela de conversa aberta: o botão flutuante do menu não aparece nela (MobileSidebarLauncher) e, no celular, o
// aviso fica no topo para não cobrir a caixa de resposta (SnackbarContainer, #2206).
export const useTelaDeConversa = () => {
  const route = useRoute();
  const listaNova = useListaNova();
  // #2211: com a lista nova, a conversa vazia ("Escrever" na busca da lista) também é tela de conversa.
  return computed(
    () =>
      CONVERSATION_ROUTES.includes(route?.name) ||
      (listaNova.value && Boolean(pedidoDeConversaVazia(route?.query)))
  );
};
