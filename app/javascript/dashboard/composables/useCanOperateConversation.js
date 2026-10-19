import { computed, unref } from 'vue';
import { useStore } from 'dashboard/composables/store';

// Quem só lê (conversation_view sem o trio conversation_*) vê a conversa sem operar (#1800): sem responder,
// atribuir, mudar status, etiquetar nem marcar como lida. O servidor recusa do mesmo jeito (ConversationPolicy#show?).
export function useCanOperateConversation(conversation) {
  const store = useStore();
  return computed(() =>
    store.getters.canOperateConversation(unref(conversation))
  );
}
