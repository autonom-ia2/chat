// Figurinha do WhatsApp (#1702). O servidor guarda como foto com a marca `is_sticker`
// no anexo; a tela da conversa recebe as chaves em camelCase e a lista de conversas,
// em snake_case.
export const eFigurinha = anexo =>
  anexo?.isSticker === true || anexo?.is_sticker === true;

export const ultimaEFigurinha = mensagem =>
  eFigurinha(mensagem?.attachments?.[0]);
