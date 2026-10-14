import { computed, ref } from 'vue';
import { useAlert } from 'dashboard/composables';

// #1423 — "Marcar como cliente / Desfazer" no card (base de clientes,
// #1144/#1258): a mesma rota e a mesma permissão da ficha do contato
// (registros de relacionamento), com a confirmação de lá.
const CLIENTE = 'CONTACTS_LAYOUT.DETAILS.CUSTOMER';

export const useCardCliente = ({ t, store, card, podeRegistros, aoMudar }) => {
  const dialogo = ref(null);
  const virar = ref(true);
  const salvando = ref(false);
  const chave = computed(() =>
    virar.value ? `${CLIENTE}.MARK_DIALOG` : `${CLIENTE}.UNDO_DIALOG`
  );
  const pedir = valor => {
    if (!podeRegistros.value || !card.value.contact?.id) return;
    virar.value = valor;
    dialogo.value?.open();
  };
  const confirmar = async () => {
    const id = card.value.contact?.id;
    if (!id) return;
    salvando.value = true;
    try {
      await store.dispatch('contacts/setCustomer', {
        id,
        customer: virar.value,
      });
      useAlert(
        t(`${CLIENTE}.API.${virar.value ? 'MARK_SUCCESS' : 'UNDO_SUCCESS'}`)
      );
      dialogo.value?.close();
      aoMudar();
    } catch {
      useAlert(t(`${CLIENTE}.API.ERROR`));
    } finally {
      salvando.value = false;
    }
  };
  return { dialogo, virar, salvando, chave, pedir, confirmar };
};
