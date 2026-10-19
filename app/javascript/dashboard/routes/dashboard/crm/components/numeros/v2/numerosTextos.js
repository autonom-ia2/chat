// #1871 — textos de CRM › Números por papel. Funções puras: recebem o que o
// servidor manda e devolvem a chave do i18n com os parâmetros (o componente
// chama `t`). Assim a regra de "qual frase" fica testada sem montar a tela.
// F3 (#1897): só a visão "Só eu"; a meta por pessoa chega na F4.

export const P = 'CRM_NUMEROS_V2';

// Dias 1 a 3 do mês: cedo para dizer se a meta vai bater.
export const DIAS_CEDO = 3;

export const formatarDinheiro = (
  valor,
  { locale = 'pt-BR', moeda = 'BRL' } = {}
) =>
  new Intl.NumberFormat(locale, {
    style: 'currency',
    currency: moeda,
    maximumFractionDigits: valor % 1 === 0 ? 0 : 2,
    minimumFractionDigits: valor % 1 === 0 ? 0 : 2,
  }).format(valor);

// "2026-10" -> "outubro", no fuso da conta (meio-dia do dia 15: nenhum fuso
// muda o mês).
export const nomeDoMes = (chave, { locale = 'pt-BR', fuso } = {}) => {
  const [ano, mes] = String(chave).split('-').map(Number);
  const data = new Date(Date.UTC(ano, mes - 1, 15, 12));
  return new Intl.DateTimeFormat(locale, {
    month: 'long',
    ...(fuso ? { timeZone: fuso } : {}),
  }).format(data);
};

export const comMaiuscula = texto =>
  texto ? texto.charAt(0).toLocaleUpperCase() + texto.slice(1) : texto;

export const pctDe = (feito, meta) =>
  meta ? Math.min(100, Math.round((feito / meta) * 100)) : 0;

// O título do topo: sempre com um número, até 8 palavras.
export const tituloDoTopo = (topo, mes) => {
  const { medida, feito, meta } = topo;
  const venda = medida === 'valor';
  if (!mes.fechado && mes.dia <= DIAS_CEDO) return { key: `${P}.TOPO.CEDO` };
  if (!meta) {
    if (venda)
      return {
        key: `${P}.TOPO.SEM_META_EU`,
        params: { n: topo.fechadas, valor: feito },
        plural: topo.fechadas,
      };
    return {
      key: `${P}.TOPO.SEM_META_RESOLVEU`,
      params: { n: feito },
      plural: feito,
    };
  }
  if (feito >= meta) return { key: `${P}.TOPO.BATIDA_EU` };
  if (!venda) return { key: `${P}.TOPO.RESOLVEU_EU`, params: { feito, meta } };
  return { key: `${P}.TOPO.FALTAM_EU`, params: { valor: meta - feito } };
};

const semPrazo = frase => frase.noPrazo === null || frase.noPrazo === undefined;

const chaveDaFrase = (frase, semMeta) => {
  if (frase.tipo === 'eu_vende')
    return semMeta ? ['EU_VENDE_SEM_META'] : ['EU_VENDE', frase.dias];
  if (frase.tipo === 'eu_vende_atende')
    return semPrazo(frase)
      ? ['EU_VENDE_ATENDE_SEM_PRAZO', frase.resolvidos]
      : ['EU_VENDE_ATENDE', frase.resolvidos];
  if (semPrazo(frase)) return ['EU_ATENDE_SEM_PRAZO', frase.dias];
  if (semMeta || (frase.falta !== null && frase.falta <= 0))
    return ['EU_ATENDE_SEM_FALTA'];
  return ['EU_ATENDE'];
};

// A frase do topo: até 15 palavras, o que explica o título. Sem "no prazo"
// (a conta ainda não grava o prazo por pessoa), a frase não fala de prazo.
export const fraseDoTopo = (topo, mes) => {
  const { frase } = topo;
  if (!mes.fechado && mes.dia <= DIAS_CEDO)
    return {
      key: `${P}.TOPO.FRASE.CEDO`,
      params: { dias: mes.dia, valor: topo.feito },
      plural: mes.dia,
    };
  const [chave, plural] = chaveDaFrase(frase, !topo.meta);
  return { key: `${P}.TOPO.FRASE.${chave}`, params: frase, plural };
};

const BOTOES = {
  meus_atrasados: 'MEUS_ATRASADOS',
  meus_parados: 'MEUS_PARADOS',
  meus_cards: 'MEUS_CARDS',
  meus_lembretes: 'MEUS_LEMBRETES',
  meus_casos: 'MEUS_CASOS',
};

export const botaoDoTopo = botao => ({
  key: `${P}.TOPO.BOTAO.${BOTOES[botao.tipo]}`,
  params: { n: botao.n, valor: botao.valor },
  plural: botao.n,
});

// Próximo passo: no máximo 2 itens e no máximo 1 faixa amarela.
export const MAX_PROXIMO = 2;
export const proximoPasso = itens => {
  let avisos = 0;
  return itens.slice(0, MAX_PROXIMO).map(item => {
    const aviso = Boolean(item.aviso) && avisos === 0;
    if (aviso) avisos += 1;
    return { ...item, aviso };
  });
};
