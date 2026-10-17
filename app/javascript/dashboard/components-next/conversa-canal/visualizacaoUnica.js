// Visualização única do WhatsApp (#1702). O servidor guarda a mídia como qualquer
// outra, com a marca `is_view_once` no anexo (como `is_sticker`), e a tela mostra
// a mídia com um rótulo (decisão do Rodrigo: o atendimento guarda o que o cliente
// mandou).
// A tela da conversa recebe as chaves em camelCase; a lista de conversas, em snake_case.
export const eVisualizacaoUnica = anexo =>
  anexo?.isViewOnce === true || anexo?.is_view_once === true;

export const temVisualizacaoUnica = anexos =>
  Array.isArray(anexos) && anexos.some(eVisualizacaoUnica);

export const ultimaEVisualizacaoUnica = mensagem =>
  temVisualizacaoUnica(mensagem?.attachments);
