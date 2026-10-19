import { computed } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';
import { getUserPermissions } from 'dashboard/helper/permissionsHelper';
import { readsOnlyConversations } from 'dashboard/store/modules/conversations/helpers';

// Quem só lê conversas (#1800) não começa conversa nova, em nenhum ponto de entrada: a
// mesma regra do "nova conversa" do menu (Sidebar.vue). Usado pela ponte da gaveta e pelo
// "Escrever" da caixa de e-mail (#1809).
export const usePodeComecarConversa = () => {
  const currentUser = useMapGetter('getCurrentUser');
  const accountId = useMapGetter('getCurrentAccountId');
  return computed(
    () =>
      !readsOnlyConversations(
        getUserPermissions(currentUser.value, accountId.value)
      )
  );
};
