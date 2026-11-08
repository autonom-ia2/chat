// Os atributos que a WAHA grava no contato para achar a conversa dele no WhatsApp
// (o chat id e as formas jid e lid). São internos: não aparecem em tela nenhuma.
// As chaves são as de app/services/waha/contact_chat_id.rb (CHAT_ID, JID e LID);
// mudou lá, muda aqui.
//
// Quem esconde são as duas fontes de definições do frontend: os getters de
// store/modules/attributes.js e o estado de composables/useRelationships.js. As
// definições continuam existindo no servidor e no store, e os valores não são
// tocados (o servidor mescla custom_attributes ao gravar): a WAHA depende deles
// para achar o contato pelo filtro.
export const ATRIBUTOS_INTERNOS_DO_WHATSAPP = Object.freeze([
  'waha_whatsapp_chat_id',
  'waha_whatsapp_jid',
  'waha_whatsapp_lid',
]);

export const ehAtributoInternoDoWhatsapp = chave =>
  ATRIBUTOS_INTERNOS_DO_WHATSAPP.includes(chave);

// As definições sem as internas do WhatsApp, na mesma ordem. Aceita a definição
// como vem da API (attribute_key) ou já em camelCase (attributeKey), como sai do
// getter attributes/getContactAttributes.
export const semAtributosInternosDoWhatsapp = (definicoes = []) =>
  definicoes.filter(
    definicao =>
      !ehAtributoInternoDoWhatsapp(
        definicao?.attribute_key ?? definicao?.attributeKey
      )
  );
