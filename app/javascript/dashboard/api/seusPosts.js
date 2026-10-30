/* global axios */
import ApiClient from './ApiClient';

// Seus posts (#2302, F1 #2304): the account's Instagram and Facebook Page
// posts, read through their inboxes (SeusPosts::Leitura). 403 when the seat
// has no posts_view; 404 when the profile is not in the account.
//
// F2 (#2305), behind seus_posts_comentarios: one post and its comments, and
// the actions on a comment (SeusPostsComentariosController). Writes need
// posts_manage; without seeing the profile's inbox, 403 not_inbox_member.
// Text goes in `content` only (the Rails log filters it).
class SeusPostsAPI extends ApiClient {
  constructor() {
    super('seus_posts', { accountScoped: true });
  }

  // { days, from, to, perfil, perfis: [{ id, network, name }] }
  get({ perfil, days }) {
    return axios.get(this.url, { params: { perfil, days } });
  }

  postUrl(postId) {
    return `${this.url}/posts/${encodeURIComponent(postId)}`;
  }

  commentUrl(postId, commentId) {
    return `${this.postUrl(postId)}/comments/${encodeURIComponent(commentId)}`;
  }

  // { perfil, status, can_manage, post, normal, comments: { status, comments, total, next_cursor } }
  getPost({ perfil, postId }) {
    return axios.get(this.postUrl(postId), { params: { perfil } });
  }

  // { status, comments, total, next_cursor }
  getComments({ perfil, postId, after }) {
    return axios.get(`${this.postUrl(postId)}/comments`, {
      params: { perfil, after },
    });
  }

  reply({ perfil, postId, commentId, content }) {
    return axios.post(`${this.commentUrl(postId, commentId)}/reply`, {
      perfil,
      content,
    });
  }

  // Instagram only: { sent_at, conversation_path }.
  privateReply({ perfil, postId, commentId, content }) {
    return axios.post(`${this.commentUrl(postId, commentId)}/private_reply`, {
      perfil,
      content,
    });
  }

  // Instagram only: "Não foi enviado", for a private reply without confirmation.
  releasePrivateReply({ perfil, postId, commentId }) {
    return axios.post(
      `${this.commentUrl(postId, commentId)}/private_reply/release`,
      { perfil }
    );
  }

  hide({ perfil, postId, commentId, hidden }) {
    return axios.post(`${this.commentUrl(postId, commentId)}/hide`, {
      perfil,
      hidden,
    });
  }

  removeComment({ perfil, postId, commentId }) {
    return axios.delete(this.commentUrl(postId, commentId), {
      params: { perfil },
    });
  }
}

export default new SeusPostsAPI();
