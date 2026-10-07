/* global axios */
// Identidade visual (#1076): kits de marca da conta e a leitura de um site.
//   GET    brand_kits?archived=      → { payload: [kit], meta: { archived_count, google_fonts } }
//   POST   brand_kits                → kit (o primeiro vira padrão); { brand_kit: {..., logo_source_url } }
//   PATCH  brand_kits/:id            → kit
//   DELETE brand_kits/:id            → arquiva (a padrão recusa: brand_kit.default_cannot_be_archived)
//   POST   brand_kits/:id/set_default | restore
//   POST   brand_kit_imports { url } → { id, status }; GET brand_kit_imports/:id → { status, proposal }
import ApiClient from './ApiClient';

class BrandKitsAPI extends ApiClient {
  constructor() {
    super('brand_kits', { accountScoped: true });
    this.siteReadings = new ApiClient('brand_kit_imports', {
      accountScoped: true,
    });
  }

  list({ archived = false } = {}) {
    return axios.get(this.url, { params: archived ? { archived: true } : {} });
  }

  save(id, brandKit) {
    return id
      ? axios.patch(`${this.url}/${id}`, { brand_kit: brandKit })
      : axios.post(this.url, { brand_kit: brandKit });
  }

  uploadLogo(id, file) {
    const body = new FormData();
    body.append('brand_kit[logo]', file);
    return axios.patch(`${this.url}/${id}`, body);
  }

  archive(id) {
    return axios.delete(`${this.url}/${id}`);
  }

  setDefault(id) {
    return axios.post(`${this.url}/${id}/set_default`);
  }

  restore(id) {
    return axios.post(`${this.url}/${id}/restore`);
  }

  readSite(url) {
    return axios.post(this.siteReadings.url, { url });
  }

  siteReading(importId) {
    return axios.get(`${this.siteReadings.url}/${importId}`);
  }
}

export default new BrandKitsAPI();
