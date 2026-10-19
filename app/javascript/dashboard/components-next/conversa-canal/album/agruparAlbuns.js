// Álbum de fotos e vídeos (#1702). A Cloud API entrega uma mensagem por foto; no app,
// fotos e vídeos mandados juntos viram um balão-mosaico, com a legenda embaixo
// (AlbumDoWhatsapp). Só o álbum de verdade junta: foto mandada uma a uma fica solta.
// - Recebido: a Cloud entrega o "pai" do álbum como não suportada (unsupported_kind
//   'unknown') logo antes das fotos (22 de 22 em produção, out/2026, seguidos de 2+
//   mídias em até 30 s). O álbum começa nesse marcador, junta as fotos/vídeos do mesmo
//   cliente que vêm logo depois, até 30 s do marcador, e para no 1º que não entra. O
//   marcador some da lista. Sem marcador, cada foto fica solta.
// - WAHA: o marcador próprio traz a contagem (albumDoWaha). O balão do álbum é o do
//   marcador, do começo ao fim (a chave não muda e o balão não remonta), e a grade nasce
//   e fica no tamanho anunciado: o que não chegou fica reservado, com "Não chegou"
//   depois da janela. Nunca volta ao mosaico só das fotos que chegaram.
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
import {
  contagemDoWaha,
  eMarcadorDoWaha,
  temMarcaDoWaha,
  temRemetente,
} from './albumDoWaha';

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
// crescer) ou se algo cortou a sequência (não cresce mais). O item recusado corta a
// sequência e fica solto.
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

// WAHA: como o da Cloud, até a quantidade anunciada. A foto que chega depois da janela
// do marcador ainda ocupa a vaga se vier até 30 s depois da anterior do álbum, sem nada
// no meio. O item recusado não ocupa vaga: corta a sequência e fica solto.
const itensDoAnuncio = (lista, inicio, esperados, { fuso, abreBloco }) => {
  const marcador = lista[inicio];
  const itens = [];
  for (let i = inicio + 1; i < lista.length; i += 1) {
    if (itens.length >= esperados) break;
    const atual = lista[i];
    const anterior = itens.at(-1) ?? marcador;
    const entra =
      podeEntrarNoAlbum(atual) &&
      !(itens.length && abreBloco(atual)) &&
      dentroDaJanela(anterior, atual, JANELA_DO_ALBUM_EM_SEGUNDOS) &&
      continuaASequencia(marcador, atual, fuso);
    if (!entra) break;
    itens.push(atual);
  }
  return itens;
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

// A janela do marcador, no relógio do navegador (`agora`, segundos). Fecha no que vier
// primeiro: 30 s depois de criado (idade negativa, de relógio atrasado, conta como 0) ou
// 30 s depois que esta tela o viu (`vistoEm`), o que limita o "Recebendo fotos…" de um
// relógio atrasado. Sem foto nenhuma, só conta o visto: com o relógio adiantado, o
// marcador não vira "mensagem não carregada" antes de 30 s à vista. O visto só vale
// para marcador recente (idade, no relógio do navegador, abaixo de 5 min): ao abrir uma
// conversa antiga, o álbum que nunca chegou já aparece como "mensagem não carregada".
// Sem `agora`, fechada; sem `vistoEm`, só a idade.
export const IDADE_DO_MARCADOR_RECENTE_EM_SEGUNDOS = 5 * 60;

const janelaDoMarcador = (marcador, { agora, vistoEm }, semFoto) => {
  if (agora === undefined) return { aberta: false };
  const recente =
    agora - marcador.createdAt < IDADE_DO_MARCADOR_RECENTE_EM_SEGUNDOS;
  const visto = recente ? vistoEm?.(marcador.id) : undefined;
  const fimPeloVisto =
    visto === undefined ? Infinity : visto + JANELA_DO_ALBUM_EM_SEGUNDOS;
  // Idade negativa conta como 0: a janela anda com o relógio até ele alcançar a criação.
  const fimPelaIdade =
    Math.min(marcador.createdAt, agora) + JANELA_DO_ALBUM_EM_SEGUNDOS;
  const ate =
    semFoto && visto !== undefined
      ? fimPeloVisto
      : Math.min(fimPelaIdade, fimPeloVisto);
  return { aberta: agora <= ate, ate };
};

// Da Cloud: o álbum chegando (mesmo com 0 ou 1 item), o álbum pronto (2+) ou nada.
// Chegando sem item nenhum, o balão do álbum é o do próprio marcador. O álbum do
// marcador é desenhado em quadrados (a forma com que chegou), pronto ou não.
const albumDoMarcador = (lista, inicio, opcoes) => {
  const marcador = lista[inicio];
  const { itens, noFim } = itensDoMarcador(lista, inicio, opcoes);
  const passo = itens.length + 1;
  const janela = janelaDoMarcador(marcador, opcoes, !itens.length);
  if (noFim && janela.aberta) {
    const noMarcador = !itens.length;
    return {
      passo,
      chave: noMarcador ? marcador.id : itens[0].id,
      itens,
      escondeMarcador: !noMarcador,
      emQuadrados: true,
      chegada: { esperados: null, noMarcador, ate: janela.ate },
    };
  }
  if (itens.length < MINIMO_DO_ALBUM) return { passo: 1 };
  return {
    passo,
    chave: itens[0].id,
    itens,
    escondeMarcador: true,
    emQuadrados: true,
  };
};

// Marcador do WAHA que não abre álbum: some, e as fotos ficam soltas.
const SEM_ALBUM = { passo: 1, escondeMarcador: true };

// Do WAHA: o balão é sempre o do marcador, na grade do tamanho anunciado. Não abre
// álbum em grupo (toda recebida vem com o contato do grupo, e a foto de outro
// participante entraria; `whatsapp_api_group`, #1741), com contagem inválida nem sem
// remetente. Sem foto nenhuma e com a janela fechada, o marcador fica como o da Cloud
// ("mensagem não carregada").
const albumDoAnuncio = (lista, inicio, opcoes) => {
  const marcador = lista[inicio];
  const esperados = contagemDoWaha(marcador);
  if (opcoes.grupo || esperados === null || !temRemetente(marcador)) {
    return SEM_ALBUM;
  }
  const itens = itensDoAnuncio(lista, inicio, esperados, opcoes);
  const janela = janelaDoMarcador(marcador, opcoes, !itens.length);
  const chegando = janela.aberta && itens.length < esperados;
  if (!itens.length && !chegando) return { passo: 1 };
  return {
    passo: itens.length + 1,
    chave: marcador.id,
    itens,
    anunciados: esperados,
    ...(chegando
      ? { chegada: { esperados, noMarcador: true, ate: janela.ate } }
      : {}),
  };
};

const albumDoEnvio = (lista, inicio, opcoes) => {
  const itens = itensDoEnvio(lista, inicio, opcoes);
  if (itens.length < MINIMO_DO_ALBUM) return { passo: 1 };
  return { passo: itens.length, chave: itens[0].id, itens };
};

// O marcador do WAHA vem antes: depois do paraOBalao ele também parece o da Cloud.
const albumQueComecaEm = (lista, inicio, opcoes) => {
  const mensagem = lista[inicio];
  if (temMarcaDoWaha(mensagem)) return albumDoAnuncio(lista, inicio, opcoes);
  if (eMarcadorDeAlbum(mensagem)) return albumDoMarcador(lista, inicio, opcoes);
  if (abreEnvio(mensagem)) return albumDoEnvio(lista, inicio, opcoes);
  return { passo: 1 };
};

// Devolve os álbuns (Map: id do balão que desenha o álbum -> mensagens, na ordem da
// conversa), os ids dos marcadores que somem da lista, os álbuns ainda chegando
// (Map: mesmo id -> { esperados, noMarcador, ate }), os desenhados em quadrados (Set de
// ids, os da Cloud que vieram de um marcador) e os anunciados pelo WAHA (Map: mesmo id
// -> quantos). `abreBloco` (opcional) diz quem não pode ficar escondido dentro do álbum
// anterior, como a 1ª não lida, que leva a etiqueta "não lidas" acima dela. `agora`
// (segundos, relógio do navegador) liga o álbum chegando (#1831); `vistoEm(id)` diz
// quando esta tela viu o marcador. `grupo`: conversa de grupo.
export const agruparDaConversa = (
  lista,
  { fuso, abreBloco = () => false, agora, vistoEm, grupo = false } = {}
) => {
  const albuns = new Map();
  const marcadores = new Set();
  const chegadas = new Map();
  const emQuadrados = new Set();
  const anunciados = new Map();
  const opcoes = { fuso, abreBloco, agora, vistoEm, grupo };
  let i = 0;
  while (i < lista.length) {
    const album = albumQueComecaEm(lista, i, opcoes);
    if (album.escondeMarcador) marcadores.add(lista[i].id);
    if (album.chave !== undefined) albuns.set(album.chave, album.itens);
    if (album.chegada) chegadas.set(album.chave, album.chegada);
    if (album.emQuadrados) emQuadrados.add(album.chave);
    if (album.anunciados) anunciados.set(album.chave, album.anunciados);
    i += album.passo;
  }
  return { albuns, marcadores, chegadas, emQuadrados, anunciados };
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

// Quadros do álbum (#1831). Enviado pela plataforma: o mosaico de sempre. Da Cloud:
// quadrados de 2 em 2, que só crescem no fim; o quadro que já apareceu não muda de
// tamanho nem de lugar, nem quando a janela fecha. Chegando, a linha incompleta (ou o
// álbum ainda sem foto) ganha quadros reservados. Mais de 4: "+N" no 4º, como sempre.
// Do WAHA (`esperados`): o mosaico do tamanho anunciado, chegando e depois, com os
// quadros que faltam reservados (entram no "+N").
export const quadrosDoAlbum = (
  itens,
  { emQuadrados = false, chegando = false, esperados = null } = {}
) => {
  if (esperados > 0) {
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

// A forma de cada quadro, como no app: 2 lado a lado em pé, 3 com o 1º largo em cima,
// o resto quadrado. Em quadrados, tudo quadrado. O balão troca o nome pela classe.
export const FORMAS = { QUADRADO: 'quadrado', ALTO: 'alto', LARGO: 'largo' };

export const formaDoQuadro = (mosaico, posicao) => {
  if (mosaico.emQuadrados) return FORMAS.QUADRADO;
  const quantos = mosaico.quadros.length;
  if (quantos === 2) return FORMAS.ALTO;
  if (quantos === 3 && posicao === 0) return FORMAS.LARGO;
  return FORMAS.QUADRADO;
};
