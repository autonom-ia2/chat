// Qual texto do balão está escrito no formato do WhatsApp (#1732). Só com a pele.
// - Recebida do cliente: escrita no app → formato do WhatsApp.
// - Enviada pelo próprio celular (eco da coexistência) e modelo da Meta: idem.
// - Enviada pelo painel, robô ou API: guardada em markdown e convertida no envio
//   (WhatsAppRenderer na Cloud; conector no WAHA). O markdown de sempre já mostra o
//   que o cliente recebe, então fica como está.
// - Nota privada: nunca sai para o cliente; markdown de sempre (com menções).
import { computed } from 'vue';
import { useMessageContext } from '../message/provider.js';
import { MESSAGE_TYPES } from '../message/constants';
import { PELES, usePele } from './pele';

export const escritoNoWhatsapp = ({
  messageType,
  privada,
  contentAttributes,
  additionalAttributes,
}) => {
  if (privada) return false;
  if (messageType === MESSAGE_TYPES.INCOMING) return true;
  if (messageType !== MESSAGE_TYPES.OUTGOING) return false;
  return (
    !!contentAttributes?.externalEcho ||
    !!additionalAttributes?.templateParams?.name
  );
};

export const useFormatoDoWhatsapp = () => {
  const pele = usePele();
  const {
    messageType,
    private: privada,
    contentAttributes,
    additionalAttributes,
  } = useMessageContext();

  return computed(
    () =>
      pele.value === PELES.WHATSAPP &&
      escritoNoWhatsapp({
        messageType: messageType.value,
        privada: privada?.value,
        contentAttributes: contentAttributes?.value,
        additionalAttributes: additionalAttributes?.value,
      })
  );
};
