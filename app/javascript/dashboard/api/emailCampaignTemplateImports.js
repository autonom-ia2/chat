/* global axios */
import ApiClient from './ApiClient';

// "Trazer meu modelo" (#1099): importa um e-mail feito em outra plataforma.
//   POST template_imports            colar (content), arquivo (file) ou endereço (url) -> 202 { id, status }
//   GET  template_imports            a última importação da pessoa ainda em andamento ou por ver
//   GET  template_imports/:id        status, passo, prévia do original, resultado e o que trava salvar
//   POST template_imports/:id/fix    resolve um aviso (imagem, campo, trecho) no servidor
//   POST template_imports/:id/save   guarda em "Meus modelos" (o navegador manda só o nome)
const MULTIPART = { headers: { 'Content-Type': 'multipart/form-data' } };

const formOf = fields => {
  const form = new FormData();
  Object.entries(fields).forEach(([key, value]) => {
    if (value !== undefined && value !== null) form.append(key, value);
  });
  return form;
};

class EmailCampaignTemplateImportsAPI extends ApiClient {
  constructor() {
    super('email_campaigns/template_imports', { accountScoped: true });
  }

  latest() {
    return axios.get(this.url);
  }

  start({ kind, content, file, url }) {
    if (kind === 'file') {
      return axios.post(
        this.url,
        formOf({ source_kind: kind, file }),
        MULTIPART
      );
    }
    return axios.post(this.url, { source_kind: kind, content, url });
  }

  show(id) {
    return axios.get(`${this.url}/${id}`);
  }

  fix(id, { kind, target, choice, value, file }) {
    if (file) {
      return axios.post(
        `${this.url}/${id}/fix`,
        formOf({ kind, target, choice, file }),
        MULTIPART
      );
    }
    return axios.post(`${this.url}/${id}/fix`, { kind, target, choice, value });
  }

  save(id, name) {
    return axios.post(`${this.url}/${id}/save`, { name });
  }
}

export default new EmailCampaignTemplateImportsAPI();
