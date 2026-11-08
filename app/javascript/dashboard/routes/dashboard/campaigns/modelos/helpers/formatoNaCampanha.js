// O que a campanha pede de cada formato novo antes de enviar (#1334), lido da
// estrutura do modelo da Meta (`modelo.template`), nunca do texto. Sem
// expressão regular.
//   cupom      → botão "Copiar código": o código que todos recebem;
//   validade   → oferta por tempo limitado que mostra a contagem: até quando;
//   topo       → foto, vídeo ou documento no topo (#1465): o aprovado, guardado
//                com o modelo, ou um arquivo escolhido agora;
//   cartoes    → carrossel: a foto ou o vídeo de cada cartão (o aprovado,
//                guardado com o modelo, ou um arquivo escolhido agora);
//   catalogo / formulario → nada a preencher, só o aviso do que acontece;
//   produtos  → um, vários ou carrossel de produtos do catálogo (#1418): os
//               produtos escolhidos (produtosNaCampanha.js).
// Código de verificação não vai em campanha.
import {
  isFutureSchedule,
  scheduleToUtc,
} from 'dashboard/components-next/CampaignJourney/scheduleTime';
import {
  levaProdutos,
  pedidoDeProdutos,
  produtosParaEnvio,
  produtosPendentes,
} from './produtosNaCampanha';

const maiusculo = valor => String(valor || '').toUpperCase();
const componente = (template, tipo) =>
  (template?.components || []).find(item => maiusculo(item?.type) === tipo);
const botoes = template => componente(template, 'BUTTONS')?.buttons || [];

// O envio do Chatwoot recusa cupom com mais de 15 caracteres (o teto da oferta).
export const CODIGO_MAXIMO = 15;
// O que o seletor de arquivo aceita no topo e em cada cartão (tipos da Meta;
// o vídeo .mov ou fora do H.264 é convertido no servidor, #2370).
export const ACEITA = {
  foto: 'image/jpeg,image/png',
  video: 'video/mp4,video/quicktime,.mp4,.mov',
  documento: 'application/pdf',
};
// Topo de mídia do modelo → o tipo da tela.
const MIDIA_DO_TOPO = { IMAGE: 'foto', VIDEO: 'video', DOCUMENT: 'documento' };

// Cartão de produto (carrossel de produtos): topo PRODUCT, sem foto nossa.
const semMidia = cartao => {
  const topo = (cartao?.components || []).find(
    item => maiusculo(item?.type) === 'HEADER'
  );
  return !['IMAGE', 'VIDEO'].includes(maiusculo(topo?.format));
};

// Cartão com campo ({{1}}) no texto ou no fim do link: a campanha ainda não liga
// esses campos, então o modelo não é oferecido (melhor do que a Meta recusar
// cada envio). Os carrosséis feitos no Chat2You não têm campo nos cartões.
const cartaoComCampo = cartao =>
  (cartao?.components || []).some(
    item =>
      (item?.text || '').includes('{{') ||
      (item?.buttons || []).some(botao => (botao?.url || '').includes('{{'))
  );

// Motivo para não oferecer o modelo na campanha (vazio = pode ir).
// #1418: `produtosLigados`: flag whatsapp_campaign_products da conta;
// `comCatalogo`: a conta do WhatsApp da caixa tem catálogo conectado.
export const formatoQueNaoVai = (
  template,
  { produtosLigados = false, comCatalogo = false } = {}
) => {
  if (maiusculo(template?.category) === 'AUTHENTICATION') return 'CODIGO';
  const tipos = botoes(template).map(botao => maiusculo(botao?.type));
  if (tipos.includes('OTP')) return 'CODIGO';
  if (levaProdutos(template)) {
    if (!produtosLigados) return 'PRODUTOS';
    return comCatalogo ? '' : 'SEM_CATALOGO';
  }
  const cartoes = componente(template, 'CAROUSEL')?.cards || [];
  if (cartoes.some(semMidia)) return 'PRODUTOS';
  if (cartoes.some(cartaoComCampo)) return 'CARTAO_COM_CAMPO';
  return '';
};

// #1456: cupom, oferta com prazo ou carrossel só chegam no modelo completo.
// Com eles a campanha não oferece a mensagem escrita das últimas 24 h (quem a
// recebesse perderia a oferta). Mesma regra no servidor:
// Whatsapp::Templates::SendableFormat.offer_format?.
export const soModeloCompleto = template =>
  levaProdutos(template) ||
  botoes(template).some(botao => maiusculo(botao?.type) === 'COPY_CODE') ||
  ['LIMITED_TIME_OFFER', 'CAROUSEL'].some(tipo =>
    Boolean(componente(template, tipo))
  );

// O que pedir na tela. `guardados`: arquivo aprovado de cada cartão (API).
export const oQuePedir = (template, guardados = [], topoGuardado = null) => {
  // `topoGuardado`: { nome } do arquivo do topo aprovado (API), ou null.
  const midiaDoTopo =
    MIDIA_DO_TOPO[maiusculo(componente(template, 'HEADER')?.format)];
  const lista = botoes(template);
  const indiceDoCupom = lista.findIndex(
    botao => maiusculo(botao?.type) === 'COPY_CODE'
  );
  const exemplo = lista[indiceDoCupom]?.example;
  const oferta = componente(template, 'LIMITED_TIME_OFFER');
  const produtos = pedidoDeProdutos(template);
  // Carrossel de produtos: a foto de cada cartão vem do catálogo.
  const cartoes =
    produtos?.tipo === 'carrossel'
      ? []
      : componente(template, 'CAROUSEL')?.cards || [];
  return {
    topo: midiaDoTopo
      ? { midia: midiaDoTopo, guardado: topoGuardado || null }
      : null,
    cupom:
      indiceDoCupom >= 0
        ? {
            indice: indiceDoCupom,
            exemplo: Array.isArray(exemplo) ? exemplo[0] : exemplo || '',
          }
        : null,
    validade: Boolean(oferta?.limited_time_offer?.has_expiration),
    cartoes: cartoes.map((cartao, indice) => {
      const topo = (cartao.components || []).find(
        item => maiusculo(item.type) === 'HEADER'
      );
      return {
        indice,
        midia: maiusculo(topo?.format) === 'VIDEO' ? 'video' : 'foto',
        guardado: guardados[indice] || null,
      };
    }),
    catalogo: lista.some(botao => maiusculo(botao?.type) === 'CATALOG'),
    formulario: lista.find(botao => maiusculo(botao?.type) === 'FLOW') || null,
    produtos,
  };
};

// Arquivo escolhido agora para o cartão: { referencia, nome }.
const escolhido = (valores, indice) => valores.cartoes?.[indice] || null;

// Cada pendência com a chave do texto que explica (vazio = pronto).
export const pendencias = (
  pedido,
  valores,
  { timeZone, agora = Date.now() }
) => {
  const lista = [];
  if (pedido.topo && !pedido.topo.guardado && !valores.topo?.referencia) {
    lista.push('TOPO');
  }
  if (pedido.cupom) {
    const codigo = (valores.cupom || '').trim();
    if (!codigo || codigo.length > CODIGO_MAXIMO) lista.push('CUPOM');
  }
  if (pedido.validade) {
    if (!scheduleToUtc(valores.validade, timeZone)) lista.push('VALIDADE');
    else if (!isFutureSchedule(valores.validade, timeZone, agora)) {
      lista.push('VALIDADE_PASSADA');
    }
  }
  const semArquivo = pedido.cartoes.some(
    cartao => !cartao.guardado && !escolhido(valores, cartao.indice)?.referencia
  );
  if (semArquivo) lista.push('CARTAO');
  if (produtosPendentes(pedido.produtos, valores.produtos)) {
    lista.push('PRODUTOS');
  }
  return lista;
};

// O que entra no `processed_params` da campanha (Whatsapp::Templates::SendParams).
// Topo ou cartão sem arquivo escolhido vai vazio: o servidor usa o aprovado do
// modelo. O escolhido vai como referência; o link é gerado no disparo.
export const extrasParaEnvio = (pedido, valores, { timeZone }) => {
  const extras = {};
  if (pedido.topo && valores.topo?.referencia) {
    extras.header = { media_blob: valores.topo.referencia };
  }
  if (pedido.cupom) {
    const lista = [];
    lista[pedido.cupom.indice] = {
      type: 'copy_code',
      parameter: (valores.cupom || '').trim(),
    };
    extras.buttons = lista;
  }
  if (pedido.validade) {
    const iso = scheduleToUtc(valores.validade, timeZone);
    extras.limited_time_offer = { expiration_time_ms: new Date(iso).getTime() };
  }
  if (pedido.cartoes.length) {
    extras.carousel = {
      cards: pedido.cartoes.map(cartao => {
        const arquivo = escolhido(valores, cartao.indice);
        return { header: arquivo ? { media_blob: arquivo.referencia } : {} };
      }),
    };
  }
  return pedido.produtos
    ? { ...extras, ...produtosParaEnvio(valores.produtos) }
    : extras;
};
