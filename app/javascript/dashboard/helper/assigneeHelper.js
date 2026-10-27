// #2249: quem cuida da conversa é dito por id E tipo. Pessoa (User) e robô (AgentBot,
// Captain::Assistant) moram em colunas diferentes no servidor e têm sequências de id
// independentes: comparar só o id confunde o robô 5 com a pessoa 5.
//
// Payload sem `assignee_type` conta como pessoa. O servidor manda o tipo sempre que há
// responsável (jbuilder da conversa e push_event_data); sem o tipo só fica a conversa que o
// próprio painel atribuiu a uma pessoa (mutation ASSIGN_AGENT). É a mesma leitura do resto do
// painel (agentHelper, quemEstaComAConversa).
const USER = 'User';

export const isHumanAssignee = meta =>
  Boolean(meta?.assignee?.id) && (meta.assignee_type || USER) === USER;

// O id da pessoa responsável, ou null quando ninguém cuida ou quem cuida é robô.
export const humanAssigneeId = conversation =>
  isHumanAssignee(conversation?.meta) ? conversation.meta.assignee.id : null;

export const isAssignedToUser = (conversation, userId) =>
  userId !== null &&
  userId !== undefined &&
  humanAssigneeId(conversation) === userId;
