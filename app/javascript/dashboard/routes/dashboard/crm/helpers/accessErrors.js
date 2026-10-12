// Acesso por funil (#1149): as recusas do servidor que a tela sabe explicar.
// Devolve a chave de i18n da mensagem, ou null para cair no aviso genérico.
const MENSAGENS = {
  'crm.owner_without_funnel': 'CRM_KANBAN.ACCESS.OWNER_WITHOUT_FUNNEL',
  'crm.access.card_funnel_required': 'CRM_KANBAN.ACCESS.CARD_FUNNEL_REQUIRED',
};

export const chaveDoErroDeAcesso = error =>
  MENSAGENS[error?.response?.data?.error] || null;

// Quem pode ser dono depende da caixa e do funil do card: a chave muda quando
// o card muda de funil ou de caixa, e a tela pergunta de novo.
export const chaveDoCard = card =>
  `${card.id}:${card.inbox_id ?? ''}:${card.pipeline_id ?? ''}`;

export const semDonosBarrados = (owners, barrados = []) =>
  owners.filter(owner => !barrados.includes(owner.id));
