// De onde veio a mensagem que a plataforma mandou sozinha em nome de uma pessoa (#2048). O balão
// mostra o nome da origem no lugar do nome da pessoa, como o "Agente de IA · Gabriela": a pessoa
// é dona do envio, mas não digitou. Decide só pelas marcas que o servidor grava em
// `content_attributes` (camelCase no balão, snake_case cru):
//   follow-up do CRM (`crm_follow_up_id`): "Retorno automático" quando o servidor marcou a origem
//     como retorno combinado (`crm_follow_up_origem: 'retorno'`, pela IA ou por uma pessoa); senão,
//     e nas mensagens antigas sem origem, "Follow-up automático";
//   aviso do Agendamento (`crm_booking_notice`): "Agendamento automático".
// O convite do Agendamento (`crm_booking_invite_id`) não entra: uma pessoa tocou no botão e às
// vezes editou o texto, então fica o nome dela. Regra de automação e campanha ficam como estão.
// Robô e IA ficam com o "Agente de IA" de sempre, mesmo com marca. Só o rótulo do painel
// muda; o texto que o cliente recebe é o mesmo.
import { SENDER_TYPES } from '../message/constants';

// Remetente robô como vem no objeto `sender` (agent_bot) ou no `sender_type` cru (AgentBot).
// Lista única: o formato do texto (useFormatoDoWhatsapp) usa a mesma.
const ROBOS = [
  SENDER_TYPES.AGENT_BOT,
  SENDER_TYPES.CAPTAIN_ASSISTANT,
  'AgentBot',
  'Captain::Assistant',
];
export const ehRobo = tipoDoRemetente => ROBOS.includes(tipoDoRemetente);

// Cada origem é a chave do nome dela no catálogo (conversaCanal.json).
export const ORIGENS = {
  FOLLOW_UP: 'CONVERSA_CANAL.REMETENTE.ORIGEM.FOLLOW_UP',
  RETORNO: 'CONVERSA_CANAL.REMETENTE.ORIGEM.RETORNO',
  AGENDAMENTO: 'CONVERSA_CANAL.REMETENTE.ORIGEM.AGENDAMENTO',
};

const ORIGEM_RETORNO = 'retorno';

const marca = (atributos, camel, snake) =>
  atributos?.[camel] ?? atributos?.[snake];

export const origemDoEnvio = atributos => {
  if (marca(atributos, 'crmFollowUpId', 'crm_follow_up_id')) {
    const origem = marca(
      atributos,
      'crmFollowUpOrigem',
      'crm_follow_up_origem'
    );
    return origem === ORIGEM_RETORNO ? ORIGENS.RETORNO : ORIGENS.FOLLOW_UP;
  }
  if (marca(atributos, 'crmBookingNotice', 'crm_booking_notice')) {
    return ORIGENS.AGENDAMENTO;
  }
  return null;
};

// A origem que o balão mostra: nenhuma para robô (ele já leva o nome do agente).
export const origemDaMensagem = (tipoDoRemetente, atributos) =>
  ehRobo(tipoDoRemetente) ? null : origemDoEnvio(atributos);
