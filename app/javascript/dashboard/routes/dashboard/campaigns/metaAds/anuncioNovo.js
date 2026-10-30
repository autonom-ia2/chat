// Anúncios da Meta (#2198), anúncio novo: para onde vai quem toca, o botão que a prévia mostra e o texto que sai do
// que a pessoa vende. WhatsApp vem primeiro e marcado (decisão de produto: não há dado da Meta sobre o mais usado).
//
// Na Meta: WhatsApp é OUTCOME_ENGAGEMENT + destination_type WHATSAPP + CONVERSATIONS, botão WHATSAPP_MESSAGE.
// Messenger: OUTCOME_ENGAGEMENT + MESSENGER + CONVERSATIONS, botão MESSAGE_PAGE. Instagram Direct: INSTAGRAM_DIRECT com
// botão MESSAGE_PAGE (app_destination INSTAGRAM_DIRECT); o objetivo dele sozinho não está na doc e é confirmado na
// chamada real antes da flag. Site: OUTCOME_TRAFFIC + LINK_CLICKS, link e botão LEARN_MORE ou SHOP_NOW.
export const DESTINATIONS = [
  'WHATSAPP',
  'INSTAGRAM_DIRECT',
  'MESSENGER',
  'WEBSITE',
];

export const SITE_ACTIONS = ['LEARN_MORE', 'SHOP_NOW'];

export const DESTINATION_ICONS = {
  WHATSAPP: 'i-ri-whatsapp-line',
  INSTAGRAM_DIRECT: 'i-ri-instagram-line',
  MESSENGER: 'i-ri-messenger-line',
  WEBSITE: 'i-lucide-globe',
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
export const lugaresDoDestino = (options, destination) => {
  if (!destination) return PLACEMENTS;
  const confirmed = options?.placements_by_destination?.[destination] || [];
  return PLACEMENTS.filter(
    option => option === 'AUTO' || confirmed.includes(option)
  );
};
