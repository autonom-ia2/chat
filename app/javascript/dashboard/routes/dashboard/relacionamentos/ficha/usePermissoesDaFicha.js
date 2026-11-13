import { computed } from 'vue';
import { usePolicy } from 'dashboard/composables/usePolicy';
import {
  QUEM_EDITA_CONTATO,
  usePermissoesDaLista,
} from '../lista/usePermissoesDaLista';

// #2895 — quem vê os botões de escrita da ficha. Nenhuma regra nova: são as que
// a lista já usa (lista/usePermissoesDaLista.js) e o servidor cobra. Esconder é
// só conforto; quem decide de verdade é o servidor.
//  - Alterar (da pessoa e da empresa), Marcar como cliente, Liberar e a caixa de
//    nota: quem pode editar contato. Quem só tem `contact_view` lê e não vê
//    nenhum deles;
//  - Novo card: a regra de "Criar cards" da lista (vê o CRM e pode criar card).
export const usePermissoesDaFicha = () => {
  const { checkPermissions } = usePolicy();
  const { podeCriarCards, podeExportar, podeAjustarRenovacoes } =
    usePermissoesDaLista();

  return {
    podeEditar: computed(() => checkPermissions(QUEM_EDITA_CONTATO)),
    podeCriarCards,
    // #2898 — "Exportar" no histórico do seguro: quem pode exportar contatos.
    podeExportar,
    // #2898 — "Ajustar renovações" e o convite para escolher o funil.
    podeAjustarRenovacoes,
  };
};
