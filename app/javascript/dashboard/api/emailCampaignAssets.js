/* global axios */
import ApiClient from './ApiClient';

// Wrapper p/ assets_controller (upload imagem/PDF -> {url}) + resolve_video (BE-B).
// Rotas reais (contracts BE-A/BE-B):
//   POST email_campaigns/campaigns/:id/assets        -> { url }
//   POST email_campaigns/campaigns/:id/resolve_video -> { video_url, poster_url, provider, mjml_block }
class EmailCampaignAssetsAPI extends ApiClient {
  constructor() {
    super('email_campaigns/campaigns', { accountScoped: true });
  }

  // Sobe imagem ou PDF via builder_assets. Retorna { url, signed_id? }.
  // timeout (ms) opcional: o arrastar/colar no editor não pode esperar para sempre (#2908).
  upload(campaignId, file, { timeout } = {}) {
    const formData = new FormData();
    formData.append('file', file);
    return axios.post(`${this.url}/${campaignId}/assets`, formData, {
      headers: { 'Content-Type': 'multipart/form-data' },
      ...(timeout ? { timeout } : {}),
    });
  }

  // Resolve um video por LINK (YouTube/Vimeo) OU por upload (signed_id do blob).
  // Retorna { video_url, poster_url, provider, mjml_block }.
  resolveVideo(campaignId, { url, signedId, posterSignedId } = {}) {
    return axios.post(`${this.url}/${campaignId}/resolve_video`, {
      url,
      signed_id: signedId,
      poster_signed_id: posterSignedId,
    });
  }
}

export default new EmailCampaignAssetsAPI();
