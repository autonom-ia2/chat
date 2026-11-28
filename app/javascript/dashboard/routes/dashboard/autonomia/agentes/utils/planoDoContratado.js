import { idiomaDoPainel } from 'dashboard/components-next/conversa-canal/dataDaConversa';

// #3270 — o preço e o período grátis do agente contratado, como o servidor manda (Contratados::Gratis.para_tela):
// { dias_gratis, preco_mensal_centavos, moeda, situacao: 'gratis' | 'pausado' | 'liberado', dias_restantes }.
// Nenhum número mora na tela: os dias, o valor e a moeda vêm do servidor, e o valor sai pelo Intl no idioma do painel.
export const SITUACAO = {
  GRATIS: 'gratis',
  PAUSADO: 'pausado',
  LIBERADO: 'liberado',
};

const CENTAVOS_POR_UNIDADE = 100;

// "R$ 197,00" (pt-BR) ou "R$197.00" (en).
export const precoDoPlano = (plano, locale) =>
  new Intl.NumberFormat(idiomaDoPainel(locale), {
    style: 'currency',
    currency: plano.moeda,
  }).format(plano.preco_mensal_centavos / CENTAVOS_POR_UNIDADE);

// A linha do cartão e da página do modelo: "7 dias grátis, depois R$ 197,00 por mês". A conta que já gastou os dias
// grátis (pausada) lê só o preço, porque contratar de novo não os reinicia. Sem plano: nada.
export const linhaDoPreco = (t, plano, locale) => {
  if (!plano) return '';
  const preco = precoDoPlano(plano, locale);
  if (plano.situacao === SITUACAO.PAUSADO) {
    return t('AGENTS.CONTRATADOS.PLANO.PRECO', { preco });
  }
  const dias = plano.dias_gratis;
  return t('AGENTS.CONTRATADOS.PLANO.PRECO_COM_GRATIS', { dias, preco }, dias);
};

// A página do agente mostra a faixa só durante o grátis e na pausa. Conta liberada (ou sem plano): sem faixa.
export const mostraFaixa = plano =>
  [SITUACAO.GRATIS, SITUACAO.PAUSADO].includes(plano?.situacao);

// A faixa da página do agente: durante o grátis, quantos dias faltam e o preço depois; pausado, o que aconteceu e com
// quem falar. Sem faixa (`mostraFaixa` falso): null.
export const faixaDoPlano = (t, plano, locale) => {
  if (!mostraFaixa(plano)) return null;
  if (plano.situacao === SITUACAO.PAUSADO) {
    return {
      situacao: SITUACAO.PAUSADO,
      cor: 'amber',
      icone: 'i-lucide-circle-pause',
      texto: t('AGENTS.CONTRATADOS.PLANO.FAIXA_PAUSADO'),
    };
  }
  const dias = plano.dias_restantes;
  return {
    situacao: SITUACAO.GRATIS,
    cor: 'blue',
    icone: 'i-lucide-gift',
    texto: t(
      'AGENTS.CONTRATADOS.PLANO.FAIXA_GRATIS',
      { dias, preco: precoDoPlano(plano, locale) },
      dias
    ),
  };
};
