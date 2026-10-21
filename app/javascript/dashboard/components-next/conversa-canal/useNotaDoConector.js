// A última mensagem na lista de conversas é a nota técnica antiga do conector WAHA?
// (#1941, item 2). A prévia mostra o aviso curto no lugar do texto técnico.
import { computed, toValue } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';
import { ehNotaDoConector } from './notaDoConector';

export const useNotaDoConector = mensagem => {
  const caixaPorId = useMapGetter('inboxes/getInbox');

  return computed(() => {
    const atual = toValue(mensagem);
    return ehNotaDoConector({
      caixa: caixaPorId.value(atual?.inbox_id),
      privada: atual?.private,
      conteudo: atual?.content,
    });
  });
};
