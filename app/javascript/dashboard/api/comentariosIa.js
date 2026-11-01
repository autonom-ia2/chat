/* global axios */
import ApiClient from './ApiClient';

// Comentários que viram cliente (#2212): the comment care of one post (Seus
// posts, B1) or one ad (B2). Same screen, same payloads; only the target
// changes. Contract: docs/audit/2026-10-30-2212-contrato-api.md.
//
// - post: seus_posts/posts/:post_id/..., always with ?perfil=
// - ad:   crm/meta_ads_connection/ads/:ad_id/..., no perfil
//
// Painel: { network, private_available, care, message, para_quem, phrases,
// read_old, results, unanswered, older, to_see, hidden }.
const BASE = {
  post: id => `seus_posts/posts/${encodeURIComponent(id)}`,
  ad: id => `crm/meta_ads_connection/ads/${encodeURIComponent(id)}`,
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

  // { message, para_quem, phrases, status } → Painel. Com a escrita (#2458), também `escrita`: { temas,
  // assuntoProibido, tom } do passo 2; sem ela, o servidor não mexe nesses campos.
  saveCuidado(target, { message, paraQuem, phrases, status, escrita }) {
    return axios.put(
      `${this.targetUrl(target)}/cuidado`,
      {
        message,
        para_quem: paraQuem,
        phrases,
        status,
        ...ComentariosIaAPI.escrita(escrita),
      },
      { params: ComentariosIaAPI.params(target) }
    );
  }

  // { recebe: { author, text, network, written?, kept_for_owner? } | { sample: true }, nao: { author, text } | null,
  // dono: { author, text } | null }. `escrita` (#2458): { assuntoProibido, tom }.
  previa(target, { paraQuem, escrita }) {
    return axios.post(
      `${this.targetUrl(target)}/cuidado/previa`,
      { para_quem: paraQuem, ...ComentariosIaAPI.escrita(escrita) },
      { params: ComentariosIaAPI.params(target) }
    );
  }

  static escrita(escrita) {
    if (!escrita) return {};
    const { temas, assuntoProibido, tom } = escrita;
    return {
      ...(temas ? { temas } : {}),
      assunto_proibido: assuntoProibido || '',
      tom: tom || '',
    };
  }

  // Seus posts: o começo da mensagem do passo 1, escrito pela IA a partir da
  // legenda (uma vez por legenda). { status: 'ready', message } | 'no_offer' |
  // 'no_caption'; 422 ai_unavailable.
  rascunho(target) {
    return axios.post(`${this.targetUrl(target)}/cuidado/rascunho`, null, {
      params: ComentariosIaAPI.params(target),
    });
  }

  // "O que eu vi na foto" do passo 1 (#2454): o servidor lê a foto do post uma
  // vez. { status: 'ready', text, corrected } | 'no_image' | 'unavailable'.
  foto(target) {
    return axios.post(`${this.targetUrl(target)}/cuidado/foto`, null, {
      params: ComentariosIaAPI.params(target),
    });
  }

  // A correção do dono, que vale no lugar da leitura. Mesmo formato.
  corrigirFoto(target, correction) {
    return axios.put(
      `${this.targetUrl(target)}/cuidado/foto`,
      { correction },
      { params: ComentariosIaAPI.params(target) }
    );
  }

  // { queued }
  lerAntigos(target) {
    return axios.post(`${this.targetUrl(target)}/cuidado/ler_antigos`, null, {
      params: ComentariosIaAPI.params(target),
    });
  }

  // { cuidados: [{ ad_id, care }] }: the care state of each ad (B2 badge).
  getCuidadosDosAnuncios() {
    return axios.get(`${this.url}crm/meta_ads_connection/cuidados`);
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

  // { status, waiting, private_window }: só o que o servidor conta, sem IA (#2454).
  getResumo(target) {
    return axios.get(`${this.targetUrl(target)}/resumo`, {
      params: ComentariosIaAPI.params(target),
    });
  }
}

export default new ComentariosIaAPI();
