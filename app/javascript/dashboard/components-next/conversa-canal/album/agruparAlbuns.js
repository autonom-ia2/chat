// Álbum de fotos e vídeos (#1702). A Cloud API entrega uma mensagem por foto; no app,
// fotos e vídeos mandados juntos viram um balão-mosaico, com a legenda embaixo
// (AlbumDoWhatsapp). Só o álbum de verdade junta: foto mandada uma a uma fica solta.
// - Recebido: a Cloud entrega o "pai" do álbum como não suportada (unsupported_kind
//   'unknown') logo antes das fotos (22 de 22 em produção, out/2026, seguidos de 2+
//   mídias em até 30 s). O álbum começa nesse marcador, junta as fotos/vídeos do mesmo
//   cliente que vêm logo depois, até 30 s do marcador, e para no 1º que não entra. O
//   marcador some da lista. Sem marcador, cada foto fica solta. O WAHA anuncia o álbum
//   com um marcador próprio, que traz a contagem (albumDoWaha): a grade já nasce no
//   mosaico final, com os quadros que faltam reservados.
// - Chegando (#1831): as fotos vêm uma a uma, de 11 a 19 s depois do marcador. Enquanto
//   a janela do marcador está aberta e nada cortou a sequência, o álbum já aparece, com
//   "Recebendo fotos…" e quadros reservados, desde o marcador sozinho. Nenhuma foto do
//   álbum aparece solta antes de entrar nele. O álbum do marcador fica em quadrados de
//   2 em 2, chegando e depois: fechada a janela, nenhum quadro muda de lugar.
// - Enviado pela plataforma: várias fotos do mesmo envio são criadas quase juntas
//   (até 3 s entre uma e outra) e seguem em álbum, como o app faz para quem manda junto.
import {
  ATTACHMENT_TYPES,
  MESSAGE_STATUS,
  MESSAGE_TYPES,
} from '../../message/constants';
import { continuaASequencia } from '../useSequenciaDaConversa';
import { eFigurinha } from '../figurinha';
import { eVisualizacaoUnica } from '../visualizacaoUnica';
import { deModeloOuCampanha } from '../encaminhar/selecaoParaEncaminhar';
import { contagemDoWaha, eMarcadorDoWaha } from './albumDoWaha';

// Itens a partir dos quais a sequência vira álbum.
export const MINIMO_DO_ALBUM = 2;
// Recebido: até quanto depois do marcador um item ainda é do álbum.
export const JANELA_DO_ALBUM_EM_SEGUNDOS = 30;
// Enviado: itens do mesmo envio nascem no mesmo segundo ou quase.
export const JANELA_DO_ENVIO_EM_SEGUNDOS = 3;
// Quantos quadros o mosaico mostra; o resto vira "+N" sobre o último.
export const QUADROS_DO_MOSAICO = 4;

const TIPOS_DO_ALBUM = [ATTACHMENT_TYPES.IMAGE, ATTACHMENT_TYPES.VIDEO];

const LADOS_DO_ALBUM = [MESSAGE_TYPES.INCOMING, MESSAGE_TYPES.OUTGOING];

// Só foto ou vídeo sozinho (com ou sem legenda), do cliente ou da empresa, sem resposta
// citada, que não falhou. Apagada pelo cliente fica solta, com o selo dela.
export const podeEntrarNoAlbum = mensagem => {
  const anexos = mensagem.attachments || [];
  const atributos = mensagem.contentAttributes || {};
  if (!LADOS_DO_ALBUM.includes(mensagem.messageType)) return false;
  if (anexos.length !== 1) return false;
  if (!TIPOS_DO_ALBUM.includes(anexos[0].fileType)) return false;
  // Figurinha fica sempre solta, como no app (é foto só no tipo do anexo).
  if (eFigurinha(anexos[0])) return false;
  // Visualização única e modelo/campanha ficam soltos, com o rótulo e as regras deles
  // (não se encaminham; no mosaico iriam junto).
  if (eVisualizacaoUnica(anexos[0]) || deModeloOuCampanha(mensagem)) {
    return false;
  }
  if (mensagem.private || mensagem.status === MESSAGE_STATUS.FAILED) {
    return false;
  }
  return !(
    atributos.inReplyTo ||
    atributos.deleted ||
    atributos.deletedByContactAt ||
    atributos.isUnsupported ||
    atributos.imageType
  );
};

// O "pai" do álbum que a Cloud entrega como não suportada, do cliente. Com
// hybridRecovery (chat#1489) é uma mensagem de verdade que o WhatsApp API busca no
// celular (modelo, botões, lista), não o marcador: fica à vista, e as fotos, soltas.
const eMarcadorDaCloud = mensagem =>
  mensagem?.messageType === MESSAGE_TYPES.INCOMING &&
  !mensagem.private &&
  mensagem.contentAttributes?.isUnsupported === true &&
  mensagem.contentAttributes?.unsupportedKind === 'unknown' &&
  !mensagem.contentAttributes?.hybridRecovery;

export const eMarcadorDeAlbum = mensagem =>
  eMarcadorDaCloud(mensagem) || eMarcadorDoWaha(mensagem);

const dentroDaJanela = (desde, atual, janela) => {
  const espera = atual.createdAt - desde.createdAt;
  return espera >= 0 && espera <= janela;
};

// Recebido: do marcador em diante, enquanto o item entra, é da mesma pessoa e chega
// até 30 s depois do marcador. `noFim` diz se a lista acabou (o álbum ainda pode
// crescer) ou se algo cortou a sequência (não cresce mais).
const itensDoMarcador = (lista, inicio, { fuso, abreBloco }) => {
  const marcador = lista[inicio];
  const itens = [];
  for (let i = inicio + 1; i < lista.length; i += 1) {
    const atual = lista[i];
    const entra =
      podeEntrarNoAlbum(atual) &&
      !(itens.length && abreBloco(atual)) &&
      dentroDaJanela(marcador, atual, JANELA_DO_ALBUM_EM_SEGUNDOS) &&
      continuaASequencia(marcador, atual, fuso);
    if (!entra) return { itens, noFim: false };
    itens.push(atual);
  }
  return { itens, noFim: true };
};

// Enviado: itens nossos seguidos, criados até 3 s um do outro, pela mesma pessoa.
const itensDoEnvio = (lista, inicio, { fuso, abreBloco }) => {
  const itens = [lista[inicio]];
  for (let i = inicio + 1; i < lista.length; i += 1) {
    const anterior = itens.at(-1);
    const atual = lista[i];
    const entra =
      atual.messageType === MESSAGE_TYPES.OUTGOING &&
      podeEntrarNoAlbum(atual) &&
      !abreBloco(atual) &&
      dentroDaJanela(anterior, atual, JANELA_DO_ENVIO_EM_SEGUNDOS) &&
      continuaASequencia(anterior, atual, fuso);
    if (!entra) break;
    itens.push(atual);
  }
  return itens;
};

const abreEnvio = mensagem =>
  mensagem.messageType === MESSAGE_TYPES.OUTGOING &&
  podeEntrarNoAlbum(mensagem);

// Até quando (segundos) o álbum do marcador ainda recebe fotos.
export const fimDaChegada = marcador =>
  marcador.createdAt + JANELA_DO_ALBUM_EM_SEGUNDOS;

// Ainda chegando: a lista acabou no álbum, falta foto anunciada (ou a contagem é
// desconhecida) e a janela do marcador não fechou. Sem `agora`, nada está chegando.
const aindaChegando = ({ marcador, itens, noFim, esperados, agora }) => {
  if (agora === undefined || !noFim) return false;
  if (esperados && itens.length >= esperados) return false;
  return agora <= fimDaChegada(marcador);
};

// Do marcador: o álbum chegando (mesmo com 0 ou 1 item), o álbum pronto (2+) ou nada.
// Chegando sem item nenhum, o balão do álbum é o do próprio marcador. O álbum do
// marcador é desenhado em quadrados (a forma com que chegou), pronto ou não. Com a
// contagem do WAHA, o mosaico final desde o início (sem quadrados).
const albumDoMarcador = (lista, inicio, opcoes) => {
  const marcador = lista[inicio];
  const { itens, noFim } = itensDoMarcador(lista, inicio, opcoes);
  const esperados = contagemDoWaha(marcador);
  const emQuadrados = !esperados;
  const passo = itens.length + 1;
  if (
    aindaChegando({ marcador, itens, noFim, esperados, agora: opcoes.agora })
  ) {
    const noMarcador = !itens.length;
    return {
      passo,
      chave: noMarcador ? marcador.id : itens[0].id,
      itens,
      escondeMarcador: !noMarcador,
      emQuadrados,
      chegada: { esperados, noMarcador, ate: fimDaChegada(marcador) },
    };
  }
  if (itens.length < MINIMO_DO_ALBUM) return { passo: 1 };
  return {
    passo,
    chave: itens[0].id,
    itens,
    escondeMarcador: true,
    emQuadrados,
  };
};

const albumDoEnvio = (lista, inicio, opcoes) => {
  const itens = itensDoEnvio(lista, inicio, opcoes);
  if (itens.length < MINIMO_DO_ALBUM) return { passo: 1 };
  return { passo: itens.length, chave: itens[0].id, itens };
};

const albumQueComecaEm = (lista, inicio, opcoes) => {
  const mensagem = lista[inicio];
  if (eMarcadorDeAlbum(mensagem)) return albumDoMarcador(lista, inicio, opcoes);
  if (abreEnvio(mensagem)) return albumDoEnvio(lista, inicio, opcoes);
  return { passo: 1 };
};

// Devolve os álbuns (Map: id do balão que desenha o álbum -> mensagens, na ordem da
// conversa), os ids dos marcadores que somem da lista, os álbuns ainda chegando
// (Map: mesmo id -> { esperados, noMarcador, ate }) e os desenhados em quadrados (Set de ids, os
// que vieram de um marcador). `abreBloco` (opcional) diz quem
// não pode ficar escondido dentro do álbum anterior, como a 1ª não lida, que leva a
// etiqueta "não lidas" acima dela. `agora` (segundos) liga o álbum chegando (#1831).
export const agruparDaConversa = (
  lista,
  { fuso, abreBloco = () => false, agora } = {}
) => {
  const albuns = new Map();
  const marcadores = new Set();
  const chegadas = new Map();
  const emQuadrados = new Set();
  const opcoes = { fuso, abreBloco, agora };
  let i = 0;
  while (i < lista.length) {
    const album = albumQueComecaEm(lista, i, opcoes);
    if (album.escondeMarcador) marcadores.add(lista[i].id);
    if (album.chave !== undefined) albuns.set(album.chave, album.itens);
    if (album.chegada) chegadas.set(album.chave, album.chegada);
    if (album.emQuadrados) emQuadrados.add(album.chave);
    i += album.passo;
  }
  return { albuns, marcadores, chegadas, emQuadrados };
};

export const agruparAlbuns = (lista, opcoes) =>
  agruparDaConversa(lista, opcoes).albuns;

// Do menos para o mais adiantado: o álbum mostra o tique do item mais atrasado.
const ORDEM_DOS_TIQUES = [
  MESSAGE_STATUS.PROGRESS,
  MESSAGE_STATUS.SENT,
  MESSAGE_STATUS.DELIVERED,
  MESSAGE_STATUS.READ,
];

export const tiqueDoAlbum = itens =>
  itens
    .map(item => item.status)
    .reduce(
      (menor, status) =>
        ORDEM_DOS_TIQUES.indexOf(status) < ORDEM_DOS_TIQUES.indexOf(menor)
          ? status
          : menor,
      itens[0]?.status
    );

// Legendas do álbum, na ordem dos itens (normalmente só uma).
export const legendasDoAlbum = itens =>
  itens
    .filter(item => item.content?.trim())
    .map(item => ({ id: item.id, texto: item.content }));

// Reações de todos os itens juntas, para o selo do álbum.
export const atributosDoAlbum = itens => ({
  ...(itens[0]?.contentAttributes || {}),
  reactions: itens.flatMap(item =>
    Array.isArray(item.contentAttributes?.reactions)
      ? item.contentAttributes.reactions
      : []
  ),
});

// Quadros visíveis e quantos ficam escondidos atrás do "+N" do último.
export const quadrosDoMosaico = itens => {
  const quadros = itens.slice(0, QUADROS_DO_MOSAICO);
  const escondidos =
    itens.length > QUADROS_DO_MOSAICO
      ? itens.length - (QUADROS_DO_MOSAICO - 1)
      : 0;
  return { quadros, escondidos };
};

// Quadro reservado: a foto ainda não chegou.
export const VAGA = null;
// Grade em quadrados: de 2 em 2, a linha incompleta fechada por um reservado.
const COLUNAS_DA_GRADE = 2;

// Quadros do álbum (#1831). Enviado pela plataforma: o mosaico de sempre. Do marcador:
// quadrados de 2 em 2, que só crescem no fim; o quadro que já apareceu não muda de
// tamanho nem de lugar, nem quando a janela fecha. Chegando, a linha incompleta (ou o
// álbum ainda sem foto) ganha quadros reservados. Mais de 4: "+N" no 4º, como sempre.
// Chegando com a contagem do WAHA: o mosaico final desde já, com os quadros que faltam
// reservados (entram no "+N").
export const quadrosDoAlbum = (
  itens,
  { emQuadrados = false, chegando = false, esperados = null } = {}
) => {
  if (chegando && esperados >= MINIMO_DO_ALBUM) {
    const total = Math.max(esperados, itens.length);
    const vagas = Array.from({ length: total }, (_, i) => itens[i] ?? VAGA);
    return { ...quadrosDoMosaico(vagas), emQuadrados: false };
  }
  const { quadros, escondidos } = quadrosDoMosaico(itens);
  if (!emQuadrados) return { quadros, escondidos, emQuadrados: false };
  const faltam = quadros.length
    ? quadros.length % COLUNAS_DA_GRADE
    : COLUNAS_DA_GRADE;
  const reservados = chegando ? faltam : 0;
  return {
    quadros: [...quadros, ...Array(reservados).fill(VAGA)],
    escondidos,
    emQuadrados: true,
  };
};
