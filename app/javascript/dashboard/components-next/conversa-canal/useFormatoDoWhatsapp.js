// Qual texto do balão está escrito no formato do WhatsApp (#1732). Só com a pele.
// - Recebida do cliente: escrita no app → formato do WhatsApp.
// - Enviada pelo próprio celular (eco da coexistência) e modelo da Meta: idem.
// - Robô, IA ou envio automático: escreve no dialeto do WhatsApp misturado com markdown
//   (*x* e **x** negrito). O envio pela Cloud lê igual (WhatsAppDaPeleRenderer, automatico:).
// - Pessoa digitando no painel: guardado em markdown (o editor grava itálico como *x*) e
//   convertido no envio. O markdown de sempre já mostra o que o cliente recebe.
// - Nota privada: nunca sai para o cliente; markdown de sempre (com menções).
// Só muda a forma de mostrar; o texto gravado não muda.
import { computed } from 'vue';
import MessageFormatter from 'shared/helpers/MessageFormatter.js';
import { useCamelCase } from 'dashboard/composables/useTransformKeys';
import { useMessageContext } from '../message/provider.js';
import { MESSAGE_TYPES } from '../message/constants';
import { PELES, usePele } from './pele';
import { formatarWhatsapp } from './formatacaoWhatsapp';
import { ehRobo } from './origemDoEnvio';

// As marcas de envio automático em nome de pessoa: espelho de
// Autonomia::Agents::Operate::PessoaDaEquipe (MARCAS_DE_ENVIO_AUTOMATICO e MARCAS_DE_CAMPANHA),
// a lista única que o envio (Messages::EnvioAutomatico) também lê.
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
  ehRobo(tipoDoRemetente) ||
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

// HTML do texto no formato dado; sem formato (null), o markdown de sempre.
export const formatarNoFormato = (texto, formato) =>
  formato
    ? formatarWhatsapp(texto, { tolerante: formato === FORMATOS.ROBO })
    : new MessageFormatter(texto).formattedMessage;

// O formato de uma mensagem inteira (a citada), venha com chaves do servidor ou em camelCase.
export const formatoDaMensagem = mensagem => {
  const m = useCamelCase(mensagem || {}, { deep: true });
  return formatoDoTexto({
    messageType: m.messageType,
    privada: m.private,
    tipoDoRemetente: m.sender?.type ?? m.senderType,
    contentAttributes: m.contentAttributes,
    additionalAttributes: m.additionalAttributes,
  });
};

// Prévia da mensagem citada (só com a pele): o texto lido como o balão dela o mostra.
export const previaDaCitada = mensagem =>
  formatarNoFormato(mensagem.content, formatoDaMensagem(mensagem));

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
