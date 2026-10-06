/* global axios */
// Importar contatos (#1006): the journey's contact import (docs/campaigns/publicos/contact-imports-1006.md).
import ApiClient from './ApiClient';

class ContactImportsAPI extends ApiClient {
  constructor() {
    super('contact_imports', { accountScoped: true });
  }

  upload(file, { createCompanies = true } = {}) {
    const formData = new FormData();
    formData.append('import_file', file);
    formData.append('create_companies', String(createCompanies));
    return axios.post(this.url, formData, {
      headers: { 'Content-Type': 'multipart/form-data' },
    });
  }

  chooseColumns(id, mapping) {
    return axios.patch(`${this.url}/${id}/columns`, mapping);
  }

  setCompanies(id, createCompanies) {
    return axios.patch(`${this.url}/${id}/companies`, {
      create_companies: createCompanies,
    });
  }

  confirm(id) {
    return axios.post(`${this.url}/${id}/confirm`);
  }

  downloadProblems(id) {
    return axios.get(`${this.url}/${id}/download`, { responseType: 'text' });
  }
}

export default new ContactImportsAPI();
