/* global axios */
import ApiClient from './ApiClient';

// O que a conversa precisa para mandar modelo de produto e carrossel (#1716),
// para quem atende a caixa (sem a tela de Modelos). Uma caixa por chamada.
// GET  inboxes/:inboxId/whatsapp_conversation_assets/catalog   → { catalog: { name, product_count } | null }
// GET  …/products?q=&after=&ids[]=                              → { payload: [{ id, name, price, sale_price, image_url, available }], meta: { after } }
// GET  …/template?name=&language=                               → { fields, card_media: [{ card_index, file_name, preview_url, blob_signed_id }] }
// POST …/media (multipart `file`)                               → { blob_signed_id, file_name }
class WhatsappConversationAssetsAPI extends ApiClient {
  constructor() {
    super('', { accountScoped: true });
  }

  base(inboxId) {
    return `${this.url}inboxes/${inboxId}/whatsapp_conversation_assets`;
  }

  getCatalog(inboxId) {
    return axios.get(`${this.base(inboxId)}/catalog`);
  }

  getProducts(inboxId, { search = '', after = '', ids = [] } = {}) {
    return axios.get(`${this.base(inboxId)}/products`, {
      params: {
        ...(search ? { q: search } : {}),
        ...(after ? { after } : {}),
        ...(ids.length ? { ids } : {}),
      },
    });
  }

  getTemplate(inboxId, { name, language }) {
    return axios.get(`${this.base(inboxId)}/template`, {
      params: { name, language },
    });
  }

  uploadPhoto(inboxId, file) {
    const body = new FormData();
    body.append('file', file);
    return axios.post(`${this.base(inboxId)}/media`, body);
  }
}

export default new WhatsappConversationAssetsAPI();
