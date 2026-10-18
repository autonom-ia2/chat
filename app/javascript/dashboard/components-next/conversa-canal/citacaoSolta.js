// Citação "solta" (#1709): o cliente respondeu a uma mensagem que não está nesta
// conversa. O servidor grava content_attributes.quoted_message:
// - achada noutra conversa: { messageId, conversationId, content (até 280), senderType, attachmentType };
// - não achada: { messageId: null, content (o trecho que o celular mandou), fromMe, hasMedia,
//   unverified: true }.
// Com `unverified`, o trecho veio só do aparelho do cliente e ninguém conferiu: um app
// modificado forja o `fromMe`. Então a citação não é atribuída a ninguém (nem à
// empresa, nem ao cliente) e avisa que não foi conferida. `fromMe` só vale sem ela.
// Na mesma conversa vem `in_reply_to`, que a citação de sempre (CitacaoDoWhatsapp) já desenha.

// Tipos de anexo que a citação mostra com ícone e nome, como o app ("📷 Foto").
export const ANEXOS_DA_CITACAO = [
  'image',
  'video',
  'audio',
  'file',
  'location',
  'contact',
];

export const citacaoSolta = atributos => {
  const citada = atributos?.quotedMessage;
  if (!citada || typeof citada !== 'object') return null;
  const tipo = ANEXOS_DA_CITACAO.includes(citada.attachmentType)
    ? citada.attachmentType
    : null;
  const naoConferida = citada.unverified === true;
  return {
    naoConferida,
    // Do número da empresa: mandada pelo celular (fromMe) ou por alguém do painel.
    daEmpresa:
      !naoConferida &&
      (citada.fromMe === true ||
        (Boolean(citada.senderType) && citada.senderType !== 'Contact')),
    texto: typeof citada.content === 'string' ? citada.content.trim() : '',
    anexo: tipo || (citada.hasMedia === true ? 'midia' : null),
    outraConversa: Boolean(citada.messageId && citada.conversationId),
  };
};
