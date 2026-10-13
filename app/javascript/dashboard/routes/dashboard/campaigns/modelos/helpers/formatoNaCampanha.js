// O que a campanha pede de cada formato novo antes de enviar (#1334), lido da
// estrutura do modelo da Meta (`modelo.template`), nunca do texto. Sem
// expressão regular.
//   cupom      → botão "Copiar código": o código que todos recebem;
//   validade   → oferta por tempo limitado que mostra a contagem: até quando;
//   cartoes    → carrossel: a foto ou o vídeo de cada cartão (o aprovado,
//                guardado com o modelo, ou um arquivo escolhido agora);
//   catalogo / formulario → nada a preencher, só o aviso do que acontece.
// Código de verificação e produtos escolhidos do catálogo não vão em campanha.
import {
  isFutureSchedule,
  scheduleToUtc,
} from 'dashboard/components-next/CampaignJourney/scheduleTime';

const maiusculo = valor => String(valor || '').toUpperCase();
const componente = (template, tipo) =>
  (template?.components || []).find(item => maiusculo(item?.type) === tipo);
const botoes = template => componente(template, 'BUTTONS')?.buttons || [];

// O envio do Chatwoot recusa cupom com mais de 15 caracteres (o teto da oferta).
export const CODIGO_MAXIMO = 15;
// O que o seletor de arquivo aceita em cada cartão (tipos da Meta).
export const ACEITA_NO_CARTAO = {
  foto: 'image/jpeg,image/png',
  video: 'video/mp4',
};

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
export const formatoQueNaoVai = template => {
  if (maiusculo(template?.category) === 'AUTHENTICATION') return 'CODIGO';
  const tipos = botoes(template).map(botao => maiusculo(botao?.type));
  if (tipos.includes('OTP')) return 'CODIGO';
  if (['MPM', 'SPM'].some(tipo => tipos.includes(tipo))) return 'PRODUTOS';
  const cartoes = componente(template, 'CAROUSEL')?.cards || [];
  if (cartoes.some(semMidia)) return 'PRODUTOS';
  if (cartoes.some(cartaoComCampo)) return 'CARTAO_COM_CAMPO';
  return '';
};

// O que pedir na tela. `guardados`: arquivo aprovado de cada cartão (API).
export const oQuePedir = (template, guardados = []) => {
  const lista = botoes(template);
  const indiceDoCupom = lista.findIndex(
    botao => maiusculo(botao?.type) === 'COPY_CODE'
  );
  const exemplo = lista[indiceDoCupom]?.example;
  const oferta = componente(template, 'LIMITED_TIME_OFFER');
  const cartoes = componente(template, 'CAROUSEL')?.cards || [];
  return {
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
  return lista;
};

// O que entra no `processed_params` da campanha (Whatsapp::Templates::SendParams).
// Cartão sem arquivo escolhido vai vazio: o servidor usa o aprovado do modelo.
export const extrasParaEnvio = (pedido, valores, { timeZone }) => {
  const extras = {};
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
  return extras;
};
