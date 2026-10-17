// Qual texto do balão está escrito no formato do WhatsApp (#1732). Só com a pele.
// - Recebida do cliente: escrita no app → formato do WhatsApp.
// - Enviada pelo próprio celular (eco da coexistência) e modelo da Meta: idem.
// - Robô, IA ou envio automático: escreve no dialeto do WhatsApp misturado com markdown
//   (*x* e **x** negrito). O envio pela Cloud lê igual (WhatsAppRenderer, automatico:).
// - Pessoa digitando no painel: guardado em markdown (o editor grava itálico como *x*) e
//   convertido no envio. O markdown de sempre já mostra o que o cliente recebe.
// - Nota privada: nunca sai para o cliente; markdown de sempre (com menções).
// Só muda a forma de mostrar; o texto gravado não muda.
import { computed } from 'vue';
import { useMessageContext } from '../message/provider.js';
import { MESSAGE_TYPES, SENDER_TYPES } from '../message/constants';
import { PELES, usePele } from './pele';
import { formatarWhatsapp } from './formatacaoWhatsapp';

// Remetente como vem no objeto `sender` (agent_bot) ou no `sender_type` cru (AgentBot).
const ROBOS = [
  SENDER_TYPES.AGENT_BOT,
  SENDER_TYPES.CAPTAIN_ASSISTANT,
  'AgentBot',
  'Captain::Assistant',
];
// As marcas de envio automático em nome de pessoa: espelho de Messages::EnvioAutomatico.
const MARCAS_DE_ENVIO_AUTOMATICO = [
  'automationRuleId',
  'crmFollowUpId',
  'crmBookingInviteId',
  'crmBookingNotice',
];
const MARCAS_DE_CAMPANHA = ['campaignId', 'whatsappApiCampaignId'];

export const FORMATOS = { APP: 'app', ROBO: 'robo' };

export const envioAutomatico = ({
  tipoDoRemetente,
  contentAttributes,
  additionalAttributes,
}) =>
  ROBOS.includes(tipoDoRemetente) ||
  MARCAS_DE_ENVIO_AUTOMATICO.some(marca => !!contentAttributes?.[marca]) ||
  MARCAS_DE_CAMPANHA.some(marca => !!additionalAttributes?.[marca]);

// O formato do texto, ou null quando é markdown (o de sempre).
export const formatoDoTexto = mensagem => {
  const { messageType, privada, contentAttributes, additionalAttributes } =
    mensagem;
  if (privada) return null;
  if (messageType === MESSAGE_TYPES.INCOMING) return FORMATOS.APP;
  if (messageType !== MESSAGE_TYPES.OUTGOING) return null;
  if (
    contentAttributes?.externalEcho ||
    additionalAttributes?.templateParams?.name
  ) {
    return FORMATOS.APP;
  }
  return envioAutomatico(mensagem) ? FORMATOS.ROBO : null;
};

// Função que formata o texto no jeito do WhatsApp, ou null (fica o markdown de sempre).
export const useFormatoDoWhatsapp = () => {
  const pele = usePele();
  const {
    messageType,
    private: privada,
    sender,
    senderType,
    contentAttributes,
    additionalAttributes,
  } = useMessageContext();

  return computed(() => {
    if (pele.value !== PELES.WHATSAPP) return null;
    const formato = formatoDoTexto({
      messageType: messageType.value,
      privada: privada?.value,
      tipoDoRemetente: sender?.value?.type ?? senderType?.value,
      contentAttributes: contentAttributes?.value,
      additionalAttributes: additionalAttributes?.value,
    });
    if (!formato) return null;
    const tolerante = formato === FORMATOS.ROBO;
    return texto => formatarWhatsapp(texto, { tolerante });
  });
};
