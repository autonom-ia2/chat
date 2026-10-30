import CrmMetaAdsConnectionAPI from 'dashboard/api/crmMetaAdsConnection';
import { capaEmArquivo } from './midiaDoAnuncio';
import { siteNormalizado } from './anuncioNovo';
import { amountCents, decimalAmount } from './dinheiroDoAnuncio';

// Anúncios da Meta (#2198), o Gerenciador simples (flag meta_ads_criar): o que a tela pede ao servidor para criar
// anúncio, mudar orçamento e datas e listar os pausados. Valores em reais (a Meta guarda em centavos; o servidor
// converte). Orçamento: { level: 'adset' | 'campaign', object_name, kind: 'daily' | 'lifetime', amount, currency,
// start_time, end_time, started, ads_count, active_ads_count, min_daily, max_daily, can_change }.

// O servidor manda o valor como texto decimal ("20.57"), nunca float. A tela faz as contas em centavos inteiros
// (`amount_cents`); `amount` em número é só para mostrar.
const orcamentoNaTela = budget =>
  budget
    ? {
        ...budget,
        amount: Number(budget.amount),
        amount_cents: amountCents(budget.amount),
      }
    : budget;

export const lerOpcoesDeCriacao = async () => {
  const { data } = await CrmMetaAdsConnectionAPI.createOptions();
  return data.options;
};

// Posts para impulsionar (#2339), da Página escolhida e do Instagram dela: { posts, instagram_posts, posts_error }.
// `posts_error`: o servidor não conseguiu ler um dos lados; a tela diz isso, nunca "sem posts".
export const lerPostsParaImpulsionar = async pageId => {
  const { data } = await CrmMetaAdsConnectionAPI.boostPosts(pageId);
  return data;
};

// O servidor nunca devolve orçamento vazio: sem ele, devolve erro, e a tela diz que não deu para ler.
export const lerOrcamento = async adId => {
  const { data } = await CrmMetaAdsConnectionAPI.adBudget(adId);
  return orcamentoNaTela(data.budget);
};

// { amount, end_time } → orçamento novo. A Meta recusa: o erro sobe para a tela, que avisa.
export const mudarOrcamento = async (adId, changes) => {
  const { data } = await CrmMetaAdsConnectionAPI.updateAdBudget(adId, changes);
  return orcamentoNaTela(data.budget);
};

export const lerPausadosEsperando = async () => {
  const { data } = await CrmMetaAdsConnectionAPI.pausedAds();
  return (data.ads || []).map(ad => ({
    ...ad,
    budget: orcamentoNaTela(ad.budget),
  }));
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

// Quem vê, quanto e quando: igual no anúncio novo e no post impulsionado. O valor vai como texto decimal ("20.00"),
// do jeito que a pessoa digitou, sem passar por float.
const publicoEDinheiro = draft => ({
  region: draft.region === 'BR' ? 'BR' : 'STATES',
  states: draft.region === 'BR' ? [] : draft.states,
  age_min: draft.age_min,
  age_max: draft.age_max,
  special_category: Boolean(draft.special_category),
  daily_amount: decimalAmount(draft.daily_amount),
  start_date: draft.start_date,
  end_date: draft.end_date || '',
});

// Post impulsionado (#2339): o post escolhido no lugar da mídia e do texto. O número do WhatsApp só vai com post do
// Instagram (post da Página não leva o botão); o servidor confere tudo de novo, e relê o post na Meta.
const pedidoDoPost = draft => ({
  kind: 'post',
  name: draft.name.trim(),
  page_id: draft.page_id,
  post_source: draft.post_source,
  post_id: draft.post_id,
  whatsapp_number:
    draft.post_source === 'instagram' ? draft.whatsapp_number : null,
  ...publicoEDinheiro(draft),
});

// O rascunho da tela vira o pedido do anúncio novo. Só vai o que vale para o destino escolhido.
export const pedidoDoAnuncio = draft => {
  if (draft.kind === 'post') return pedidoDoPost(draft);
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
    ...publicoEDinheiro(draft),
    media: midiaNaMeta(draft.media),
    cards: draft.more_media.map(midiaNaMeta),
  };
};

// A tentativa de criar, pelo conteúdo do pedido: o mesmo pedido leva a mesma chave de idempotência até chegar uma
// resposta definitiva, e o servidor devolve o mesmo anúncio em vez de criar outro. A chave fica só na memória desta
// página; nada do pedido vai para o armazenamento do navegador. Quem garante que o mesmo pedido com outra chave (outra
// aba, outro aparelho, a tela reaberta) não cria a segunda campanha é o servidor: ele responde com a chave da tentativa
// que já cuida do pedido (`idempotency_key`), e a tela segue com ela. Pedido diferente (a pessoa mudou algo) é outra
// tentativa.
const HTTP_CONFLICT = 409;
const HTTP_SERVER_ERROR = 500;
const UUID_BYTES = 16;
const tentativas = new Map();

// UUID v4. Navegador sem `crypto.randomUUID` (página fora de HTTPS, navegador antigo): monta com getRandomValues.
export const novaChave = () => {
  if (typeof crypto.randomUUID === 'function') return crypto.randomUUID();
  const bytes = crypto.getRandomValues(new Uint8Array(UUID_BYTES));
  bytes[6] = 0x40 + (bytes[6] % 0x10); // versão 4
  bytes[8] = 0x80 + (bytes[8] % 0x40); // variante RFC 4122
  const hex = [...bytes]
    .map(byte => byte.toString(16).padStart(2, '0'))
    .join('');
  return [
    hex.slice(0, 8),
    hex.slice(8, 12),
    hex.slice(12, 16),
    hex.slice(16, 20),
    hex.slice(20),
  ].join('-');
};

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
  if (!tentativas.has(signature)) tentativas.set(signature, novaChave());
  return tentativas.get(signature);
};

// Cria pausado. `recriar`: a tentativa ficou não confirmada na Meta, a pessoa conferiu no Gerenciador de Anúncios
// que a campanha não está lá e pediu para criar de novo (mesma chave; o servidor grava na Auditoria).
export const criarAnuncio = async (pedido, { recriar = false } = {}) => {
  const signature = JSON.stringify(pedido);
  const key = chaveDoPedido(signature);
  try {
    const { data } = await CrmMetaAdsConnectionAPI.createAd({
      ...pedido,
      idempotency_key: key,
      ...(recriar ? { recreate_unconfirmed: true } : {}),
    });
    tentativas.delete(signature);
    return { ...data, budget: orcamentoNaTela(data.budget) };
  } catch (error) {
    // O servidor achou outra tentativa deste mesmo pedido: daqui em diante, é ela.
    const atual = error?.response?.data?.idempotency_key;
    if (atual) tentativas.set(signature, atual);
    if (!tentativaContinua(error)) tentativas.delete(signature);
    throw error;
  }
};

// Ao sair do fluxo de criar (e nos testes): nenhuma tentativa fica na memória.
export const esquecerTentativas = () => {
  tentativas.clear();
};
