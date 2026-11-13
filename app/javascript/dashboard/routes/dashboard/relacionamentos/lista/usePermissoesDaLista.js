import { computed } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';
import { usePolicy } from 'dashboard/composables/usePolicy';
import { useCrmPermissions } from 'dashboard/routes/dashboard/crm/composables/useCrmPermissions';
import { usePodeAjustarRenovacoes } from '../carteira/usePodeAjustarRenovacoes';

// As mesmas regras da barra de ações da lista de contatos de hoje
// (contacts/components/ContactsBulkActionBar.vue) e do servidor (ContactPolicy):
// etiquetar é de quem edita contato; apagar, do administrador ou da chave
// `contact_delete`.
export const QUEM_EDITA_CONTATO = ['administrator', 'agent', 'contact_manage'];
const QUEM_APAGA_CONTATO = ['administrator', 'contact_delete'];
// Trazer uma lista é importar contatos: a regra de ContactPolicy#import?.
const QUEM_TRAZ_LISTA = ['administrator', 'contact_manage'];
// Exportar contatos: a regra de ContactPolicy#export? (a mesma do menu da lista
// de contatos de hoje, Contacts/ContactsHeader/components/ContactMoreActions.vue).
const QUEM_EXPORTA_CONTATO = ['administrator', 'contact_export'];

// #2894 — quem vê "Criar cards", "Etiqueta" e "Apagar" na barra de ação em
// grupo da lista. Nenhuma regra nova: são as que o painel já usa. Esconder é só
// conforto; quem decide de verdade é o servidor.
//  - Criar cards: quem vê o CRM no menu (components-next/sidebar/Sidebar.vue:
//    CRM ligado na instalação e `canViewCrm`) E pode criar card
//    (`canManageCards`, a mesma chave que o servidor pede na escrita). Só ver o
//    CRM não basta: o servidor recusaria e a tela ofereceria um "tentar de
//    novo" que nunca funciona;
//  - Etiqueta: quem pode editar contato;
//  - Apagar: quem pode apagar contato;
//  - Trazer minha lista: quem pode importar contatos.
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
    // #2898 — exportar o histórico de um seguro segue a regra de exportar
    // contatos.
    podeExportar: computed(() => checkPermissions(QUEM_EXPORTA_CONTATO)),
    // #2898 — mudar onde ficam as renovações pede as duas chaves que o
    // servidor pede (carteira/usePodeAjustarRenovacoes.js).
    podeAjustarRenovacoes: usePodeAjustarRenovacoes(),
  };
};
