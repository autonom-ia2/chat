import { computed } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';
import { usePolicy } from 'dashboard/composables/usePolicy';
import { useCrmPermissions } from 'dashboard/routes/dashboard/crm/composables/useCrmPermissions';
import { QUEM_TRAZ_LISTA } from '../trazer/quemTraz';

// As mesmas regras da barra de ações da lista de contatos de hoje
// (contacts/components/ContactsBulkActionBar.vue) e do servidor (ContactPolicy):
// etiquetar é de quem edita contato; apagar, do administrador ou da chave
// `contact_delete`.
export const QUEM_EDITA_CONTATO = ['administrator', 'agent', 'contact_manage'];
const QUEM_APAGA_CONTATO = ['administrator', 'contact_delete'];

// #2894 — quem vê "Criar cards", "Etiqueta" e "Apagar" na barra de ação em
// grupo da lista. Nenhuma regra nova: são as que o painel já usa. Esconder é só
// conforto; quem decide de verdade é o servidor.
//  - Criar cards: quem vê o CRM no menu (components-next/sidebar/Sidebar.vue:
//    CRM ligado na instalação e `canViewCrm`) E pode criar card
//    (`canManageCards`, a mesma chave que o servidor pede na escrita). Só ver o
//    CRM não basta: o servidor recusaria e a tela ofereceria um "tentar de
//    novo" que nunca funciona;
//  - Etiqueta: quem pode editar contato;
//  - Apagar: quem pode apagar contato.
// #2896 — e quem vê "Trazer minha lista" no herói: quem pode importar contato
// (a mesma regra da rota `relacionamentos_trazer` e do servidor).
export const usePermissoesDaLista = () => {
  const globalConfig = useMapGetter('globalConfig/get');
  const { canViewCrm, canManageCards } = useCrmPermissions();
  const { checkPermissions } = usePolicy();

  return {
    podeCriarCards: computed(
      () =>
        globalConfig.value?.crmKanbanEnabled === true &&
        canViewCrm.value &&
        canManageCards.value
    ),
    podeEtiquetar: computed(() => checkPermissions(QUEM_EDITA_CONTATO)),
    podeApagar: computed(() => checkPermissions(QUEM_APAGA_CONTATO)),
    podeTrazer: computed(() => checkPermissions(QUEM_TRAZ_LISTA)),
  };
};
