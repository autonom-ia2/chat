// PROTÓTIPO #1334 (aguarda aprovação do Rodrigo): o que a campanha pede de
// cada formato novo antes de enviar, lido da estrutura do modelo da Meta
// (`modelo.template`), nunca do texto. Sem expressão regular.
//   cupom      → botão "Copiar código": o código que todos recebem;
//   validade   → oferta por tempo limitado que mostra a contagem: até quando;
//   cartoes    → carrossel: a foto/vídeo de cada cartão (a aprovada, guardada
//                com o modelo, ou um link);
//   catalogo / formulario → nada a preencher, só o aviso do que acontece.
// Código de verificação e catálogo com produtos escolhidos (MPM/SPM) não vão.
import { scheduleToUtc } from 'dashboard/components-next/CampaignJourney/scheduleTime';

const maiusculo = valor => String(valor || '').toUpperCase();
const componente = (template, tipo) =>
  (template?.components || []).find(item => maiusculo(item?.type) === tipo);
const botoes = template => componente(template, 'BUTTONS')?.buttons || [];

export const CODIGO_MAXIMO = 15;

// Motivo para não oferecer o modelo na campanha (vazio = pode ir).
export const formatoQueNaoVai = template => {
  if (maiusculo(template?.category) === 'AUTHENTICATION') return 'CODIGO';
  const tipos = botoes(template).map(botao => maiusculo(botao?.type));
  if (tipos.includes('OTP')) return 'CODIGO';
  if (['MPM', 'SPM'].some(tipo => tipos.includes(tipo))) return 'PRODUTOS';
  return '';
};

// O que pedir na tela. `guardados`: arquivos de cada cartão guardados com o
// modelo (adaptador falso no protótipo).
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

const linkValido = link => {
  const texto = (link || '').trim();
  return texto.startsWith('https://') || texto.startsWith('http://');
};

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
    const iso = scheduleToUtc(valores.validade, timeZone);
    if (!iso) lista.push('VALIDADE');
    else if (new Date(iso).getTime() <= agora) lista.push('VALIDADE_PASSADA');
  }
  pedido.cartoes.forEach(cartao => {
    const link = valores.cartoes?.[cartao.indice] || '';
    if (link ? !linkValido(link) : !cartao.guardado) lista.push('CARTAO');
  });
  return [...new Set(lista)];
};

// O que entra no `processed_params` da campanha (contrato do backend da #1334).
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
        const link = (valores.cartoes?.[cartao.indice] || '').trim();
        return { header: link ? { media_url: link } : {} };
      }),
    };
  }
  return extras;
};
