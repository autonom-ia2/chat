/* global axios */
import ApiClient from './ApiClient';

// Comentários que viram cliente (#2212): the comment care of one post (Seus
// posts, B1) or one ad (B2). Same screen, same payloads; only the target
// changes. Contract: docs/audit/2026-10-30-2212-contrato-api.md.
//
// - post: seus_posts/posts/:post_id/..., always with ?perfil=
// - ad:   crm/meta_ads/ads/:ad_id/..., no perfil
//
// Painel: { network, private_available, care, message, para_quem, phrases,
// read_old, results, unanswered, older, to_see, hidden }.
const BASE = {
  post: id => `seus_posts/posts/${encodeURIComponent(id)}`,
  ad: id => `crm/meta_ads/ads/${encodeURIComponent(id)}`,
};

class ComentariosIaAPI extends ApiClient {
  constructor() {
    super('', { accountScoped: true });
  }

  // `this.url` ends with "/" (empty resource): the target path goes after it.
  targetUrl({ kind, id }) {
    const base = BASE[kind];
    if (!base) throw new Error(`comentariosIa: unknown target ${kind}`);
    return `${this.url}${base(id)}`;
  }

  // Only the post target is read through a profile.
  static params({ kind, perfil }) {
    return kind === 'post' ? { perfil } : {};
  }

  getCuidado(target) {
    return axios.get(`${this.targetUrl(target)}/cuidado`, {
      params: ComentariosIaAPI.params(target),
    });
  }

  // { message, para_quem, phrases, status } → Painel
  saveCuidado(target, { message, paraQuem, phrases, status }) {
    return axios.put(
      `${this.targetUrl(target)}/cuidado`,
      { message, para_quem: paraQuem, phrases, status },
      { params: ComentariosIaAPI.params(target) }
    );
  }

  // { recebe: { author, text, network } | { sample: true }, nao: { author, text } | null }
  previa(target, { paraQuem }) {
    return axios.post(
      `${this.targetUrl(target)}/cuidado/previa`,
      { para_quem: paraQuem },
      { params: ComentariosIaAPI.params(target) }
    );
  }

  // { queued }
  lerAntigos(target) {
    return axios.post(`${this.targetUrl(target)}/cuidado/ler_antigos`, null, {
      params: ComentariosIaAPI.params(target),
    });
  }

  // Seus posts: os cuidados do perfil, para o selo e a faixa.
  // { cuidados: [{ post_id, care, network, results: { sent, replied } }] }
  getCuidados(perfil) {
    return axios.get(`${this.url}seus_posts/cuidados`, { params: { perfil } });
  }

  // "Pausar todos" / "Retomar todos" do perfil → a mesma lista.
  mudarTodos(perfil, status) {
    return axios.put(
      `${this.url}seus_posts/cuidados`,
      { status },
      { params: { perfil } }
    );
  }

  // { status, questions, questions_old, complaints, read, more }
  getResumo(target) {
    return axios.get(`${this.targetUrl(target)}/resumo`, {
      params: ComentariosIaAPI.params(target),
    });
  }
}

export default new ComentariosIaAPI();
