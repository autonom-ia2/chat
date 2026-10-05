import { FAMILIAS } from './assuntos';

// A página de um assunto (#977): o mesmo capítulo da tela inicial, com o nome curto de lá e o
// progresso de quem já viu os artigos.

// Primeiros passos: os títulos já trazem "Passo N —". Número no círculo brigaria com o do título
// quando um passo some para a conta.
export const CAPITULO_DA_TRILHA = '00';

const SEGUNDOS_POR_MINUTO = 60;

const nomesCurtos = new Map(
  FAMILIAS.flatMap(familia => familia.assuntos.map(([id, nome]) => [id, nome]))
);

// Chave de i18n do nome curto (POR_ASSUNTO.NOMES.<chave>); capítulo novo, ainda sem nome, dá null.
export const nomeCurtoDe = capituloId => nomesCurtos.get(capituloId) || null;

export const capituloPorId = (capitulos, id) =>
  capitulos.find(capitulo => capitulo.id === id && capitulo.artigos?.length) ||
  null;

const temDuracao = artigo => Number(artigo.duracao) > 0;

// Total de minutos de vídeo, arredondado para cima: 40 segundos ainda é "1 min". Sem duração em
// nenhum artigo (backend antigo), null: a tela não mostra o total.
export const minutosDeVideo = artigos => {
  const comDuracao = artigos.filter(temDuracao);
  if (!comDuracao.length) return null;
  const segundos = comDuracao.reduce(
    (soma, artigo) => soma + Number(artigo.duracao),
    0
  );
  return Math.ceil(segundos / SEGUNDOS_POR_MINUTO);
};

// Selo da miniatura: 95 → "1:35".
export const duracaoCurta = segundos => {
  if (!(Number(segundos) > 0)) return null;
  const total = Math.round(Number(segundos));
  const minutos = Math.floor(total / SEGUNDOS_POR_MINUTO);
  const resto = String(total % SEGUNDOS_POR_MINUTO).padStart(2, '0');
  return `${minutos}:${resto}`;
};

// O botão principal: o primeiro artigo ainda não visto ("Continuar"); nada visto, o primeiro
// ("Começar"); tudo visto, o primeiro de novo ("Rever do início").
export const proximoDoAssunto = (artigos, foiVisto) => {
  const vistos = artigos.filter(artigo => foiVisto(artigo.id)).length;
  if (vistos === 0) return { modo: 'COMECAR', artigo: artigos[0] };
  if (vistos === artigos.length) return { modo: 'REVER', artigo: artigos[0] };
  return {
    modo: 'CONTINUAR',
    artigo: artigos.find(artigo => !foiVisto(artigo.id)),
  };
};

// Artigo com vídeo, mesmo sem a miniatura publicada: o topo conta e a lista mostra o mesmo.
export const temVideo = artigo =>
  artigo.video === true || Boolean(artigo.poster);
