import CrmKanbanAPI from 'dashboard/api/crmKanban';

// #2710, variante 2 (card novo, casado pelo contato) — o card aberto que a página de agendamento criou para quem já
// comprou. Só dado real: a página grava `source` 'public_link' (link da página) ou 'invite' (convite) no card que ela
// cria (Crm::BookingV2::BookingCard); o "cliente desde" é o `customer_since` do contato. O canal por onde o link
// chegou (e-mail, WhatsApp) não fica gravado, então a tela não fala dele.
const DO_AGENDAMENTO = ['public_link', 'invite'];

export const clienteQueAgendou = card => {
  const contato = card?.contact;
  if (card?.status !== 'open' || !DO_AGENDAMENTO.includes(card?.source))
    return null;
  if (contato?.contact_type !== 'customer' || !contato.id) return null;
  return { contatoId: contato.id, desde: contato.customer_since || null };
};

// O card ganho da pessoa, pela API de hoje (perfil do contato), que já respeita quem pode ver cada card.
export const cardGanhoDoContato = async contatoId => {
  const { data } = await CrmKanbanAPI.getContactOpportunities(
    String(contatoId),
    { result: 'won' }
  );
  return data?.payload?.[0]?.id || null;
};
