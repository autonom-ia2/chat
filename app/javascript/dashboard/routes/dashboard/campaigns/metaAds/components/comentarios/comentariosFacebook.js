import CrmMetaAdsConnectionAPI from 'dashboard/api/crmMetaAdsConnection';

// Anúncios da Meta (#2197): comentários do post da Página no Facebook por trás do anúncio. Adaptador da aba Facebook
// da casca comum (MetaAdsComments.vue, #2196), na forma combinada com a aba Instagram:
//   listar(adId) -> { status, permalink_url, comments, total, next_cursor }, mais(adId, cursor),
//   responder(adId, id, texto), ocultar(adId, id, bool), apagar(adId, id), entrar(status, adId).
//   Linha: { id, author: { name|null, is_page }, text, created_time, hidden, can_reply, can_hide, can_delete,
//   can_reply_private, replies: [] }.
//
// Tudo ao vivo na Meta, pelo servidor (Crm::MetaAds::FacebookComments). `status`: `ready`; `no_post` (anúncio sem post
// da Página: a aba some); `needs_login` (falta pages_read_user_content/pages_manage_engagement, ou a pessoa não
// administra a Página); `no_inbox` (a conta não tem a Página como caixa do Messenger: ninguém lê, #2359);
// `not_inbox_member` (a pessoa não está nessa caixa). Falha ao ler sobe para a casca, que mostra "tente de novo";
// recusa ao agir também.
// Resposta no privado fica fora deste envio à Meta (decisão de 25/10 na #2197): exige pages_messaging, que está em
// acesso padrão, e a doc não cita anúncio. can_reply_private vem sempre false; a tela sugere o WhatsApp.

export const listar = async adId => {
  const { data } = await CrmMetaAdsConnectionAPI.facebookComments(adId);
  return data.comments;
};

export const mais = async (adId, cursor) => {
  const { data } = await CrmMetaAdsConnectionAPI.facebookComments(adId, cursor);
  return data.comments;
};

export const responder = async (adId, id, texto) => {
  const { data } = await CrmMetaAdsConnectionAPI.replyFacebookComment(
    adId,
    id,
    texto
  );
  return data;
};

export const ocultar = async (adId, id, hidden) => {
  const { data } = await CrmMetaAdsConnectionAPI.hideFacebookComment(
    adId,
    id,
    hidden
  );
  return data;
};

// Irreversível: some do Facebook. A casca confirma antes de chamar.
export const apagar = async (adId, id) => {
  const { data } = await CrmMetaAdsConnectionAPI.deleteFacebookComment(
    adId,
    id
  );
  return data;
};

// Sem a caixa da Página: a tela de conectar uma caixa do Messenger (só quem cria caixas vê o botão). Sem permissão:
// a aba Conexão, onde fica o Entrar com o Facebook, levando o anúncio em `volta`; depois de entrar e escolher a conta,
// a página volta ao anúncio (MetaAdsPage.vue).
export const entrar = (status, adId) => {
  if (status === 'no_inbox') {
    const conta = window.location.pathname.split('/campaigns')[0];
    window.location.assign(`${conta}/settings/inboxes/new/facebook`);
    return;
  }
  const query = new URLSearchParams(window.location.search);
  query.set('aba', 'conexao');
  query.set('volta', adId || query.get('anuncio') || '');
  window.location.assign(`${window.location.pathname}?${query}`);
};

export default { listar, mais, responder, ocultar, apagar, entrar };
