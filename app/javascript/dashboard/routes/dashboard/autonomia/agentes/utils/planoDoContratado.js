import { idiomaDoPainel } from 'dashboard/components-next/conversa-canal/dataDaConversa';

// #3270 — o preço e os dias grátis do agente contratado, como o servidor manda (Contratados::Gratis.para_tela):
// { dias_gratis, preco_mensal_centavos, moeda, situacao: 'gratis' | 'pausado' | 'liberado', dias_restantes }.
// Nenhum número mora na tela: os dias, o valor e a moeda vêm do servidor, e o valor sai pelo Intl no idioma do painel.
// `dias_restantes` são dias do calendário, no fuso da conta: 0 é o último dia grátis.
export const SITUACAO = {
  GRATIS: 'gratis',
  PAUSADO: 'pausado',
  LIBERADO: 'liberado',
};

const CENTAVOS_POR_UNIDADE = 100;
const ICONE_GRATIS = 'i-lucide-gift';
const ICONE_PRECO = 'i-lucide-tag';

// "R$ 197,00" (pt-BR) ou "R$197.00" (en).
export const precoDoPlano = (plano, locale) =>
  new Intl.NumberFormat(idiomaDoPainel(locale), {
    style: 'currency',
    currency: plano.moeda,
  }).format(plano.preco_mensal_centavos / CENTAVOS_POR_UNIDADE);

// A conta que já gastou os dias grátis (pausada) não ganha outros: contratar de novo não os reinicia.
const semGratis = plano => plano.situacao === SITUACAO.PAUSADO;

// A linha do cartão e da página do modelo: "7 dias grátis, depois R$ 197,00 por mês", ou, para quem já usou os dias
// grátis, "R$ 197,00 por mês. Os dias grátis já foram usados.". Sem plano: nada.
export const linhaDoPreco = (t, plano, locale) => {
  if (!plano) return '';
  const preco = precoDoPlano(plano, locale);
  if (semGratis(plano)) {
    return t('AGENTS.CONTRATADOS.PLANO.PRECO_SEM_GRATIS', { preco });
  }
  const dias = plano.dias_gratis;
  return t('AGENTS.CONTRATADOS.PLANO.PRECO_COM_GRATIS', { dias, preco }, dias);
};

// O ícone da linha do preço: o presente (o mesmo da faixa) quando há dias grátis; a etiqueta quando é só o preço.
export const iconeDoPreco = plano =>
  plano && !semGratis(plano) ? ICONE_GRATIS : ICONE_PRECO;

// A página do agente mostra a faixa só durante os dias grátis e na pausa. Conta liberada (ou sem plano): sem faixa.
export const mostraFaixa = plano =>
  [SITUACAO.GRATIS, SITUACAO.PAUSADO].includes(plano?.situacao);

const textoDosDiasGratis = (t, plano, locale) => {
  const preco = precoDoPlano(plano, locale);
  const dias = plano.dias_restantes;
  if (dias === 0) {
    return t('AGENTS.CONTRATADOS.PLANO.FAIXA_ULTIMO_DIA', { preco });
  }
  return t('AGENTS.CONTRATADOS.PLANO.FAIXA_GRATIS', { dias, preco }, dias);
};

// A faixa da página do agente. Nos dias grátis: quantos faltam (ou que hoje é o último) e o preço depois, como aviso
// (`status`). Pausado: o que aconteceu e com quem falar, como alerta (`alert`): o agente não está atendendo. Sem faixa
// (`mostraFaixa` falso): null.
export const faixaDoPlano = (t, plano, locale) => {
  if (!mostraFaixa(plano)) return null;
  if (plano.situacao === SITUACAO.PAUSADO) {
    return {
      situacao: SITUACAO.PAUSADO,
      cor: 'amber',
      papel: 'alert',
      icone: 'i-lucide-circle-pause',
      texto: t('AGENTS.CONTRATADOS.PLANO.FAIXA_PAUSADO'),
    };
  }
  return {
    situacao: SITUACAO.GRATIS,
    cor: 'blue',
    papel: 'status',
    icone: ICONE_GRATIS,
    texto: textoDosDiasGratis(t, plano, locale),
  };
};
