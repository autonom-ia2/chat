// #1992 (F5 do #1871) — textos da visão "Equipe" de CRM › Números. Funções puras,
// como as de numerosTextos (a visão "Só eu"): recebem o que o servidor manda e
// devolvem a chave do i18n com os parâmetros. O topo escolhe por aqui: escopo
// 'equipe' ou 'empresa' usa as regras abaixo; o resto segue numerosTextos.
import {
  DIAS_CEDO,
  P,
  botaoDoTopo,
  fraseDoTopo,
  tituloDoTopo,
} from './numerosTextos';

export const daEquipe = topo => ['equipe', 'empresa'].includes(topo?.escopo);

const cedo = mes => !mes.fechado && mes.dia <= DIAS_CEDO;

// #2075 — sem a chave de valores o servidor manda o R$ do topo vazio (null): o
// título e a frase falam das vendas fechadas, sem dinheiro e sem meta.
const semValor = topo => topo.medida === 'valor' && topo.feito === null;

const tituloDaEquipe = topo => {
  const { escopo, medida, feito, meta } = topo;
  const quem = escopo === 'empresa' ? 'EMPRESA' : 'EQUIPE';
  if (semValor(topo))
    return {
      key: `${P}.TOPO.FECHOU_${quem}_SEM_VALOR`,
      params: { n: topo.fechadas },
      plural: topo.fechadas,
    };
  if (medida !== 'valor') {
    if (!meta)
      return {
        key: `${P}.TOPO.SEM_META_RESOLVEU_EQUIPE`,
        params: { n: feito },
        plural: feito,
      };
    if (feito >= meta) return { key: `${P}.TOPO.BATIDA_EQUIPE` };
    return { key: `${P}.TOPO.RESOLVEU_EQUIPE`, params: { feito, meta } };
  }
  if (!meta)
    return {
      key: `${P}.TOPO.SEM_META_${quem}`,
      params: { n: topo.fechadas, valor: feito },
      plural: topo.fechadas,
    };
  if (feito >= meta) return { key: `${P}.TOPO.BATIDA_${quem}` };
  return { key: `${P}.TOPO.FALTAM_${quem}`, params: { valor: meta - feito } };
};

// A frase da empresa fala do suporte com meta só quando ela existir (hoje o
// funil de Atender não tem meta).
const chaveDaEmpresa = (frase, semMeta) => {
  if (semMeta) return 'EMPRESA_SEM_META';
  return frase.metaResolvidos ? 'EMPRESA' : 'EMPRESA_RESOLVEU';
};

const fraseSemValor = frase =>
  frase.tipo === 'empresa'
    ? { key: `${P}.TOPO.FRASE.EMPRESA_SEM_VALOR`, params: frase }
    : {
        key: `${P}.TOPO.FRASE.EQUIPE_VENDAS_SEM_VALOR`,
        params: frase,
        plural: frase.ajuda,
      };

const fraseDaEquipe = topo => {
  const { frase } = topo;
  if (semValor(topo)) return fraseSemValor(frase);
  const semMeta = !topo.meta;
  if (frase.tipo === 'empresa')
    return {
      key: `${P}.TOPO.FRASE.${chaveDaEmpresa(frase, semMeta)}`,
      params: frase,
    };
  if (frase.tipo === 'equipe_vendas')
    return semMeta
      ? { key: `${P}.TOPO.FRASE.EQUIPE_VENDAS_SEM_META`, params: frase }
      : {
          key: `${P}.TOPO.FRASE.EQUIPE_VENDAS`,
          params: frase,
          plural: frase.ajuda,
        };
  // O prazo por pessoa ainda não é gravado: sem "em cada 10 no prazo".
  return {
    key: `${P}.TOPO.FRASE.EQUIPE_ATENDE_SEM_PRAZO`,
    params: frase,
    plural: frase.lembretes,
  };
};

// Sem valor (#2075), o começo do mês também fala das vendas fechadas: a frase
// "Até agora: R$ …" não tem o que mostrar.
const textoDaEquipe = (topo, mes) =>
  daEquipe(topo) && (semValor(topo) || !cedo(mes));

export const tituloDoTopoDe = (topo, mes) =>
  textoDaEquipe(topo, mes) ? tituloDaEquipe(topo) : tituloDoTopo(topo, mes);

export const fraseDoTopoDe = (topo, mes) =>
  textoDaEquipe(topo, mes) ? fraseDaEquipe(topo) : fraseDoTopo(topo, mes);

const BOTOES_DA_EQUIPE = {
  parados: 'PARADOS',
  atrasados_equipe: 'ATRASADOS_EQUIPE',
  cards_equipe: 'CARDS_EQUIPE',
  lembretes_equipe: 'LEMBRETES_EQUIPE',
  casos_equipe: 'CASOS_EQUIPE',
};

// #2075 — os parados sem o R$ (null) quando a pessoa não vê valores.
const chaveDoBotao = botao =>
  botao.tipo === 'parados' && botao.valor === null
    ? 'PARADOS_SEM_VALOR'
    : BOTOES_DA_EQUIPE[botao.tipo];

export const botaoDoTopoDe = botao =>
  BOTOES_DA_EQUIPE[botao.tipo]
    ? {
        key: `${P}.TOPO.BOTAO.${chaveDoBotao(botao)}`,
        params: { n: botao.n, valor: botao.valor },
        plural: botao.n,
      }
    : botaoDoTopo(botao);

// "No caminho certo: Ana, Carla e você." — a pessoa que abre vem por último.
export const juntarNomes = (nomes, { e = 'e' } = {}) => {
  if (nomes.length <= 1) return nomes.join('');
  return `${nomes.slice(0, -1).join(', ')} ${e} ${nomes.at(-1)}`;
};
