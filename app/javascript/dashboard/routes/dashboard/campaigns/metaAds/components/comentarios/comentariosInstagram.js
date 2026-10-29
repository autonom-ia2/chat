// Anúncios da Meta (#2196): comentários do anúncio no Instagram. Adaptador da aba Instagram da casca comum
// (MetaAdsComments.vue), na forma combinada com a aba Facebook (#2197), sempre com o anúncio primeiro:
//   listar(adId) -> { status, account, permalink_url, comments, total, next_cursor }, mais(adId, cursor),
//   responder(adId, id, texto), ocultar(adId, id, bool), apagar(adId, id), privado(adId, id, texto), liberar(adId, id)
//   e entrar(status, adId).
// `status`: `ready`; `needs_login` (o Instagram está conectado sem a permissão de comentários); `not_connected` (o
// anúncio sai num Instagram que não está conectado ao Chat2You); `no_post` (o anúncio não aparece no Instagram).
//
// Tudo vem do servidor (Crm::MetaAds::InstagramComments), que lê a Meta ao vivo e só age em comentário da mídia do
// anúncio. Erro da Meta ou de regra rejeita a promessa: a casca avisa e não tira nada da tela.
//
// Responder no privado (Private Reply): uma mensagem só, até 7 dias depois do comentário, vai para o Direct da pessoa
// e vira conversa na caixa do Instagram. `private_reply` traz quando foi e o caminho da conversa.
import CrmMetaAdsConnectionAPI from 'dashboard/api/crmMetaAdsConnection';
import instagramClient from 'dashboard/api/channel/instagramClient';

// A caixa do Instagram de cada anúncio, da última leitura: é ela que pede o login de novo.
const caixas = {};

const corpo = async request => (await request).data;

export const listar = async adId => {
  const data = await corpo(CrmMetaAdsConnectionAPI.instagramComments(adId));
  caixas[adId] = data.inbox_id;
  return data;
};

export const mais = (adId, cursor) =>
  corpo(CrmMetaAdsConnectionAPI.instagramComments(adId, cursor));

// No Instagram a resposta também fica num nível só: responder a uma resposta vai para o comentário de cima.
export const responder = (adId, id, texto) =>
  corpo(CrmMetaAdsConnectionAPI.replyInstagramComment(adId, id, texto));

export const ocultar = (adId, id, hidden) =>
  corpo(CrmMetaAdsConnectionAPI.hideInstagramComment(adId, id, hidden));

// Irreversível: some do Instagram. A casca confirma antes de chamar.
export const apagar = (adId, id) =>
  corpo(CrmMetaAdsConnectionAPI.deleteInstagramComment(adId, id));

export const privado = (adId, id, texto) =>
  corpo(CrmMetaAdsConnectionAPI.privateReplyInstagramComment(adId, id, texto));

// "Não foi enviado": a pessoa conferiu no Direct que o privado sem confirmação não chegou; o botão volta.
export const liberar = (adId, id) =>
  corpo(CrmMetaAdsConnectionAPI.releaseInstagramPrivateReply(adId, id));

const contaAtual = () => window.location.pathname.split('/campaigns')[0];

// Sem a permissão de comentários: refazer o login da caixa do Instagram que já existe, pedindo também
// instagram_business_manage_comments (o servidor decide o escopo pelo `purpose`), e voltar a este anúncio. Sem o
// Instagram conectado: a tela de conectar uma caixa do Instagram.
export const entrar = async (status, adId) => {
  if (status !== 'needs_login' || !caixas[adId]) {
    window.location.assign(`${contaAtual()}/settings/inboxes/new/instagram`);
    return;
  }
  const { data } = await instagramClient.generateAuthorization({
    inbox_id: caixas[adId],
    return_to: 'meta_ads',
    purpose: 'meta_ads_comentarios_instagram',
    ad_id: adId,
  });
  window.location.assign(data.url);
};

// Quem chega ao fim do caminho de `entrar` (#2358, a régua de MetaAdsOrganic.vue): conectar é criar a caixa
// (inbox_manage); reautorizar pede integration_manage para gerar o link e inbox_manage na volta
// (Instagram::Testers::OauthBinding). `tem(chave)` diz se a pessoa tem a permissão (usePermissionGranted).
export const PERMISSOES_PARA_ENTRAR = ['inbox_manage', 'integration_manage'];
export const podeEntrar = (status, tem) =>
  tem('inbox_manage') &&
  (status !== 'needs_login' || tem('integration_manage'));

export default {
  listar,
  mais,
  responder,
  ocultar,
  apagar,
  privado,
  liberar,
  entrar,
  podeEntrar,
  PERMISSOES_PARA_ENTRAR,
};
