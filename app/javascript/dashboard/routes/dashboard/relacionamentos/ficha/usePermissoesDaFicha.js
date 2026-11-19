import { computed } from 'vue';
import { usePolicy } from 'dashboard/composables/usePolicy';
import { usePodeCriarLembrete } from 'dashboard/routes/dashboard/crm/components/lembrete/usePodeCriarLembrete';
import {
  QUEM_EDITA_CONTATO,
  usePermissoesDaLista,
} from '../lista/usePermissoesDaLista';

export const QUEM_VE_AS_MIDIAS = ['administrator', 'agent'];

// #2895 — quem vê os botões de escrita da ficha. Nenhuma regra nova: são as que
// a lista já usa (lista/usePermissoesDaLista.js) e o servidor cobra. Esconder é
// só conforto; quem decide de verdade é o servidor.
//  - Alterar (da pessoa e da empresa), Marcar como cliente, Liberar e a caixa de
//    nota: quem pode editar contato. Quem só tem `contact_view` lê e não vê
//    nenhum deles;
//  - Novo card: a regra de "Criar cards" da lista (vê o CRM e pode criar card).
// #3071 — as ações que vieram da ficha antiga, com as regras dela:
//  - Juntar, Bloquear, etiquetas, apagar nota e "não quer mensagens": quem pode
//    editar contato (o servidor pede `update?` nas duas pessoas do juntar);
//  - Apagar: quem pode apagar contato (administrador ou `contact_delete`, a
//    regra do "Apagar" da lista e do ContactPolicy#destroy?);
//  - Lembrete: a regra do "Novo lembrete" da ficha antiga
//    (crm/components/lembrete/usePodeCriarLembrete.js).
// #3078 — "Ver todas" as mídias da empresa: quem chega na tela de mídias (a
// rota relationships_company_media pede administrador ou agente;
// QUEM_VE_AS_MIDIAS).
export const usePermissoesDaFicha = () => {
  const { checkPermissions } = usePolicy();
  const { podeCriarCards, podeExportar, podeAjustarRenovacoes, podeApagar } =
    usePermissoesDaLista();

  return {
    podeEditar: computed(() => checkPermissions(QUEM_EDITA_CONTATO)),
    podeCriarCards,
    podeApagar,
    podeCriarLembrete: usePodeCriarLembrete(),
    // #2898 — "Exportar" no histórico do seguro: quem pode exportar contatos.
    podeExportar,
    // #2898 — "Ajustar renovações" e o convite para escolher o funil.
    podeAjustarRenovacoes,
    podeVerMidias: computed(() => checkPermissions(QUEM_VE_AS_MIDIAS)),
  };
};
