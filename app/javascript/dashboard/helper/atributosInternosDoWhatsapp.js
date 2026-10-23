// Os atributos que a WAHA grava no contato para achar a conversa dele no WhatsApp
// (o chat id e as formas jid e lid). São internos: não aparecem na lista de campos
// do contato. As chaves são as de app/services/waha/contact_chat_id.rb (CHAT_ID,
// JID e LID); mudou lá, muda aqui.
//
// Só a tela os esconde. As definições continuam existindo e os valores não são
// tocados: a WAHA depende delas para achar o contato pelo filtro.
export const ATRIBUTOS_INTERNOS_DO_WHATSAPP = Object.freeze([
  'waha_whatsapp_chat_id',
  'waha_whatsapp_jid',
  'waha_whatsapp_lid',
]);

export const ehAtributoInternoDoWhatsapp = chave =>
  ATRIBUTOS_INTERNOS_DO_WHATSAPP.includes(chave);

// As definições sem as internas do WhatsApp, na mesma ordem.
export const semAtributosInternosDoWhatsapp = (definicoes = []) =>
  definicoes.filter(
    definicao => !ehAtributoInternoDoWhatsapp(definicao?.attribute_key)
  );
