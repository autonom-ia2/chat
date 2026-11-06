// Anúncios da Meta (#2198), anúncio novo: para onde vai quem toca, o botão que a prévia mostra e o texto que sai do
// que a pessoa vende. WhatsApp vem primeiro e marcado (decisão de produto: não há dado da Meta sobre o mais usado).
//
// Na Meta: WhatsApp é OUTCOME_ENGAGEMENT + destination_type WHATSAPP + CONVERSATIONS, botão WHATSAPP_MESSAGE.
// Messenger: OUTCOME_ENGAGEMENT + MESSENGER + CONVERSATIONS, botão MESSAGE_PAGE. Instagram Direct: INSTAGRAM_DIRECT com
// botão MESSAGE_PAGE (app_destination INSTAGRAM_DIRECT); o objetivo dele sozinho não está na doc e é confirmado na
// chamada real antes da flag. Site: OUTCOME_TRAFFIC + LINK_CLICKS, link e botão LEARN_MORE ou SHOP_NOW.
// Perfil do Instagram (#2564): OUTCOME_TRAFFIC + INSTAGRAM_PROFILE + PROFILE_VISIT, botão VIEW_INSTAGRAM_PROFILE. A
// Meta não aceita anúncio de perfil com categoria especial (seguro, crédito…): a tela pede outro destino.
export const DESTINATIONS = [
  'WHATSAPP',
  'INSTAGRAM_DIRECT',
  'MESSENGER',
  'WEBSITE',
  'INSTAGRAM_PROFILE',
];

// A primeira pergunta do anúncio novo (#2564): para onde vai quem toca, em três objetivos. Conversar junta os destinos
// de conversa (o canal se troca depois, no passo da foto); site e perfil têm um destino cada.
export const GOALS = {
  CONVERSATION: ['WHATSAPP', 'INSTAGRAM_DIRECT', 'MESSENGER'],
  WEBSITE: ['WEBSITE'],
  PROFILE: ['INSTAGRAM_PROFILE'],
};
export const GOAL_ICONS = {
  CONVERSATION: 'i-lucide-message-circle',
  WEBSITE: 'i-lucide-globe',
  PROFILE: 'i-ri-instagram-line',
};
export const objetivoDoDestino = destination =>
  Object.keys(GOALS).find(goal => GOALS[goal].includes(destination)) || null;
// O anúncio de perfil não vai com categoria especial (doc da Meta: special_ad_categories precisa ser NONE). Post
// impulsionado não tem esse destino, mesmo que o rascunho guarde o do anúncio novo de antes.
export const perfilComCategoriaEspecial = draft =>
  draft.kind !== 'post' &&
  draft.destination === 'INSTAGRAM_PROFILE' &&
  draft.special_category === true;

export const SITE_ACTIONS = ['LEARN_MORE', 'SHOP_NOW'];

export const DESTINATION_ICONS = {
  WHATSAPP: 'i-ri-whatsapp-line',
  INSTAGRAM_DIRECT: 'i-ri-instagram-line',
  MESSENGER: 'i-ri-messenger-line',
  WEBSITE: 'i-lucide-globe',
  INSTAGRAM_PROFILE: 'i-lucide-circle-user-round',
};

// O botão do anúncio na prévia: conversa (o destino) ou o texto escolhido para o site.
export const botaoDoAnuncio = draft =>
  draft.destination === 'WEBSITE' ? draft.site_action : draft.destination;

const capitalized = value =>
  value ? value.charAt(0).toLocaleUpperCase() + value.slice(1) : '';

export const ofertaNoTexto = offer => capitalized(offer.trim());

// "bolo de pote a R$ 12" → "Bolo de pote a R$ 12. Chame no WhatsApp e faça seu pedido." (o fim muda com o destino).
const TEXT_FROM_OFFER = {
  WHATSAPP: 'CRM_KANBAN.META_ADS_HUB.CRIAR.CONTENT.TEXT_FROM_OFFER.WHATSAPP',
  INSTAGRAM_DIRECT:
    'CRM_KANBAN.META_ADS_HUB.CRIAR.CONTENT.TEXT_FROM_OFFER.INSTAGRAM_DIRECT',
  MESSENGER: 'CRM_KANBAN.META_ADS_HUB.CRIAR.CONTENT.TEXT_FROM_OFFER.MESSENGER',
  WEBSITE: 'CRM_KANBAN.META_ADS_HUB.CRIAR.CONTENT.TEXT_FROM_OFFER.WEBSITE',
  INSTAGRAM_PROFILE:
    'CRM_KANBAN.META_ADS_HUB.CRIAR.CONTENT.TEXT_FROM_OFFER.INSTAGRAM_PROFILE',
};
export const textoDaOferta = (t, offer, destination) => {
  const value = ofertaNoTexto(offer);
  return value ? t(TEXT_FROM_OFFER[destination], { offer: value }) : '';
};

// Endereço do site como o lojista digita ("lojaexemplo.com.br"): sem o começo, completa com https://. É assim que
// vai para a conferência e para a Meta.
export const siteNormalizado = value => {
  const typed = value.trim();
  if (!typed || typed.includes('://')) return typed;
  return `https://${typed}`;
};

// Endereço do site: https e um domínio com ponto. O servidor confere de novo.
export const siteValido = value => {
  try {
    const url = new URL(siteNormalizado(value));
    return url.protocol === 'https:' && url.hostname.includes('.');
  } catch {
    return false;
  }
};

// O que a chamada real já confirmou para a conta vem do servidor, nas opções de criar: `destinations` e
// `placements_by_destination`. A tela só mostra isso (e a gravação para a Meta também). Automático vale sempre: vai
// sem publisher_platforms fixo. Sem destino (post sem botão), os três lugares.
export const PLACEMENTS = ['AUTO', 'INSTAGRAM', 'FACEBOOK'];
export const destinosDaConta = options =>
  DESTINATIONS.filter(option => options?.destinations?.includes(option));
// Perfil do Instagram (#2564): só no Instagram, sem escolha (o botão leva ao perfil do Instagram).
export const lugaresDoDestino = (options, destination) => {
  if (!destination) return PLACEMENTS;
  if (destination === 'INSTAGRAM_PROFILE') return ['INSTAGRAM'];
  const confirmed = options?.placements_by_destination?.[destination] || [];
  return PLACEMENTS.filter(
    option => option === 'AUTO' || confirmed.includes(option)
  );
};
