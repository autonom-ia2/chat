// #2894 — as ações que saem da ficha. O que tem rota real leva até ela (a lista,
// a outra ficha, a conversa, o CRM); o resto mostra um aviso curto dizendo o que
// vai acontecer, sem mexer em nada.
import { useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';

export const useAcoesDaFicha = () => {
  const router = useRouter();
  const { t } = useI18n();

  const avisar = (chave, nome) => useAlert(t(chave, { nome }));

  const irPara = (name, params, query) => router.push({ name, params, query });

  return {
    avisar,
    voltarParaLista: aba =>
      irPara('relationships_home', undefined, aba ? { aba } : undefined),
    abrirPessoa: contactId => irPara('relacionamentos_pessoa', { contactId }),
    abrirEmpresa: companyId => irPara('relacionamentos_empresa', { companyId }),
    // A conversa pelo número dela, na mesma rota da caixa de entrada.
    abrirConversa: conversationId =>
      irPara('inbox_conversation', { conversation_id: conversationId }),
    // Com o id, o quadro do CRM já abre o card (`card_id`, como em
    // components-next/Relationships/RelationshipOpportunities.vue); sem ele,
    // abre só o quadro.
    abrirNoCrm: cardId =>
      irPara(
        'crm_kanban_index',
        undefined,
        cardId ? { card_id: String(cardId) } : undefined
      ),
    // O quadro do CRM já com a pessoa escolhida para o card novo
    // (`new_contact_id`, como em ContactOpportunityLink.vue).
    novoCardNoCrm: contactId =>
      irPara('crm_kanban_index', undefined, {
        new_contact_id: String(contactId),
      }),
  };
};
