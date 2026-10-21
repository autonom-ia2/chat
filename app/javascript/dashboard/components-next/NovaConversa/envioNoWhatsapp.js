// #1988 — como a mensagem da gaveta sai no WhatsApp, em funções puras.
//
// A Cloud API leva um anexo por mensagem e o texto vai como legenda (a caixa de
// resposta faz igual: ReplyBox.getMultipleMessagesPayload). Diferença de propósito:
// a legenda vai no primeiro anexo que NÃO é gravação, porque áudio no WhatsApp não tem
// legenda e o texto se perderia; só com gravações, o texto sai sozinho, antes delas.
// O WAHA recebe tudo numa mensagem só, como na caixa de resposta.
//
// Cada parte: { texto, anexos, voz }. `voz`: a parte leva a gravação do painel e sai
// como mensagem de voz (`is_voice_message`).
const parte = (texto, anexos) => ({
  texto,
  anexos,
  voz: anexos.some(anexo => anexo.isVoiceMessage),
});

export const partesDoWhatsapp = ({
  texto = '',
  anexos = [],
  umPorMensagem,
}) => {
  if (!umPorMensagem || !anexos.length) return [parte(texto, anexos)];
  const comLegenda = anexos.findIndex(anexo => !anexo.isVoiceMessage);
  const partes = anexos.map((anexo, indice) =>
    parte(indice === comLegenda ? texto : '', [anexo])
  );
  return comLegenda === -1 && texto.trim()
    ? [parte(texto, []), ...partes]
    : partes;
};
