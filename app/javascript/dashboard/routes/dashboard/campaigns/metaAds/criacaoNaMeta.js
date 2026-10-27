import CrmMetaAdsConnectionAPI from 'dashboard/api/crmMetaAdsConnection';
import { capaEmArquivo } from './midiaDoAnuncio';
import { siteNormalizado } from './anuncioNovo';

// Anúncios da Meta (#2198), o Gerenciador simples (flag meta_ads_criar): o que a tela pede ao servidor para criar
// anúncio, mudar orçamento e datas e listar os pausados. Valores em reais (a Meta guarda em centavos; o servidor
// converte). Orçamento: { level: 'adset' | 'campaign', object_name, kind: 'daily' | 'lifetime', amount, currency,
// start_time, end_time, started, ads_count, active_ads_count, min_daily, max_daily, can_change }.

export const lerOpcoesDeCriacao = async () => {
  const { data } = await CrmMetaAdsConnectionAPI.createOptions();
  return data.options;
};

// O servidor nunca devolve orçamento vazio: sem ele, devolve erro, e a tela diz que não deu para ler.
export const lerOrcamento = async adId => {
  const { data } = await CrmMetaAdsConnectionAPI.adBudget(adId);
  return data.budget;
};

// { amount, end_time } → orçamento novo. A Meta recusa: o erro sobe para a tela, que avisa.
export const mudarOrcamento = async (adId, changes) => {
  const { data } = await CrmMetaAdsConnectionAPI.updateAdBudget(adId, changes);
  return data.budget;
};

export const lerPausadosEsperando = async () => {
  const { data } = await CrmMetaAdsConnectionAPI.pausedAds();
  return data.ads || [];
};

// Sobe a mídia escolhida no celular assim que a pessoa escolhe. Foto: volta com o `hash`. Vídeo: volta com o
// `video_id`, e a capa que a tela tirou sobe também (JPEG), para o criativo levar o `image_hash` dela.
export const enviarMidia = async (media, file) => {
  const { data } = await CrmMetaAdsConnectionAPI.uploadMedia(file);
  if (media.kind === 'image') return { ...media, hash: data.media.hash };
  const cover = await CrmMetaAdsConnectionAPI.uploadMedia(
    capaEmArquivo(media.poster)
  );
  return {
    ...media,
    video_id: data.media.video_id,
    image_hash: cover.data.media.hash,
  };
};

// A mídia como o servidor espera: foto pelo `hash`; vídeo pelo `video_id` e o `hash` da capa.
const midiaNaMeta = media =>
  media.kind === 'video'
    ? { kind: 'video', video_id: media.video_id, image_hash: media.image_hash }
    : { kind: 'image', hash: media.hash };

// O rascunho da tela vira o pedido do anúncio novo. Só vai o que vale para o destino escolhido.
export const pedidoDoAnuncio = (draft, dailyAmount) => {
  const whatsapp = draft.destination === 'WHATSAPP';
  const site = draft.destination === 'WEBSITE';
  return {
    name: draft.name.trim(),
    destination: draft.destination,
    page_id: draft.page_id,
    whatsapp_number: whatsapp ? draft.whatsapp_number : null,
    site_url: site ? siteNormalizado(draft.site_url) : null,
    site_action: site ? draft.site_action : null,
    text: draft.text.trim(),
    headline: draft.headline.trim(),
    ready_message: whatsapp ? draft.ready_message.trim() : null,
    placement: draft.placement,
    region: draft.region === 'BR' ? 'BR' : 'STATES',
    states: draft.region === 'BR' ? [] : draft.states,
    age_min: draft.age_min,
    age_max: draft.age_max,
    special_category: Boolean(draft.special_category),
    daily_amount: dailyAmount,
    start_date: draft.start_date,
    end_date: draft.end_date || '',
    media: midiaNaMeta(draft.media),
    cards: draft.more_media.map(midiaNaMeta),
  };
};

// A tentativa de criar, pelo conteúdo do pedido: o mesmo pedido leva a mesma chave de idempotência até chegar uma
// resposta definitiva, e o servidor devolve o mesmo anúncio em vez de criar outro. Mora aqui, fora da tela: quem sai
// com o pedido em voo e volta (ou toca de novo) não gera chave nova. Pedido diferente (a pessoa mudou algo) é outra
// tentativa.
const HTTP_CONFLICT = 409;
const HTTP_SERVER_ERROR = 500;
const tentativas = new Map();

// Sem resposta, tempo esgotado, falha do servidor, "ainda criando" (409) ou recusa que deixou algo na Meta
// (`nothing_created: false`, que o servidor desfaz antes de criar de novo com a mesma chave): a tentativa continua.
// Só o anúncio criado ou a recusa com nada criado encerram a tentativa.
const tentativaContinua = error => {
  const response = error?.response;
  if (!response?.status) return true;
  if (response.status === HTTP_CONFLICT) return true;
  if (response.status >= HTTP_SERVER_ERROR) return true;
  return response.data?.nothing_created === false;
};

const chaveDoPedido = signature => {
  if (!tentativas.has(signature)) {
    tentativas.set(signature, crypto.randomUUID());
  }
  return tentativas.get(signature);
};

// Cria pausado.
export const criarAnuncio = async pedido => {
  const signature = JSON.stringify(pedido);
  const key = chaveDoPedido(signature);
  try {
    const { data } = await CrmMetaAdsConnectionAPI.createAd({
      ...pedido,
      idempotency_key: key,
    });
    tentativas.delete(signature);
    return data;
  } catch (error) {
    if (!tentativaContinua(error)) tentativas.delete(signature);
    throw error;
  }
};

// Para os testes: cada um começa sem tentativa pendente.
export const esquecerTentativas = () => tentativas.clear();
